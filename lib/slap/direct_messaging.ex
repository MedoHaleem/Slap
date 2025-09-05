defmodule Slap.DirectMessaging do
  alias Slap.Accounts.User
  alias Slap.Chat.{Conversation, DirectMessage, ConversationParticipant, Reaction}
  alias Slap.{Repo, Uploads}
  import Ecto.Query
  require Logger

  @pubsub Slap.PubSub

  # Configuration constants
  @default_message_limit 50
  # 1 minute window
  @rate_limit_window 60_000
  # max messages per user per conversation per window
  @rate_limit_max_messages 30

  def subscribe_to_conversation(conversation) do
    Phoenix.PubSub.subscribe(@pubsub, conversation_topic(conversation.id))
  end

  def unsubscribe_from_conversation(conversation) do
    Phoenix.PubSub.unsubscribe(@pubsub, conversation_topic(conversation.id))
  end

  defp conversation_topic(conversation_id), do: "conversation:#{conversation_id}"

  def create_conversation(attrs \\ %{}, opts \\ [])

  def create_conversation(attrs, opts) do
    # Extract options
    participants = Keyword.get(opts, :participants, [])
    participant_ids = Keyword.get(opts, :participant_ids, [])
    creator = Keyword.get(opts, :creator)

    # Validate that we don't have conflicting participant specifications
    cond do
      participants != [] and participant_ids != [] ->
        {:error,
         %Ecto.Changeset{
           action: :insert,
           errors: [participants: {"cannot specify both participants and participant_ids", []}],
           data: %Conversation{},
           valid?: false
         }}

      participants == [] and participant_ids == [] ->
        # Check if this was called from create_conversation_with_participants with empty list
        if Map.has_key?(attrs, :_called_with_participants) do
          {:error,
           %Ecto.Changeset{
             action: :insert,
             errors: [participants: {"must have at least 2 participants", []}],
             data: %Conversation{},
             valid?: false
           }}
        else
          # Simple conversation creation without participants
          %Conversation{}
          |> Conversation.changeset(attrs)
          |> Repo.insert()
        end

      participants != [] ->
        # Create conversation with user structs
        create_conversation_with_users(attrs, participants, creator)

      participant_ids != [] ->
        # Create conversation with user IDs
        create_conversation_with_ids(attrs, participant_ids)
    end
  end

  # Legacy function for backward compatibility
  def create_conversation_with_participants(attrs \\ %{}, participant_ids)
      when is_list(participant_ids) do
    # Mark that this was called with participants to enable validation
    marked_attrs = Map.put(attrs, :_called_with_participants, true)
    create_conversation(marked_attrs, participant_ids: participant_ids)
  end

  defp create_conversation_with_users(attrs, participants, creator) do
    # Include creator in participants if provided
    all_participants =
      if creator do
        [creator | participants] |> Enum.uniq_by(& &1.id)
      else
        participants |> Enum.uniq_by(& &1.id)
      end

    if length(all_participants) < 2 do
      {:error,
       %Ecto.Changeset{
         action: :insert,
         errors: [participants: {"must have at least 2 participants", []}],
         data: %Conversation{},
         valid?: false
       }}
    else
      Repo.transaction(fn ->
        with {:ok, conversation} <-
               %Conversation{}
               |> Conversation.changeset(attrs)
               |> Repo.insert(),
             {:ok, _} <- add_participants_to_conversation(conversation, all_participants) do
          conversation |> Repo.preload(conversation_participants: :user)
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  defp create_conversation_with_ids(attrs, participant_ids) do
    participant_ids = Enum.uniq(participant_ids)

    if length(participant_ids) < 2 do
      {:error,
       %Ecto.Changeset{
         action: :insert,
         errors: [participants: {"must have at least 2 participants", []}],
         data: %Conversation{},
         valid?: false
       }}
    else
      Repo.transaction(fn ->
        with {:ok, conversation} <-
               %Conversation{}
               |> Conversation.changeset(attrs)
               |> Repo.insert(),
             {:ok, _} <- add_participant_ids_to_conversation(conversation, participant_ids) do
          conversation |> Repo.preload(conversation_participants: :user)
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  defp add_participants_to_conversation(conversation, participants) do
    participants
    |> Enum.map(fn user ->
      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id
      })
    end)
    |> Enum.map(&Repo.insert/1)
    |> Enum.reduce({:ok, []}, fn
      {:ok, participant}, {:ok, acc} -> {:ok, [participant | acc]}
      {:error, error}, _ -> {:error, error}
      _, {:error, error} -> {:error, error}
    end)
  end

  defp add_participant_ids_to_conversation(conversation, participant_ids) do
    participant_ids
    |> Enum.map(fn user_id ->
      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_id: conversation.id,
        user_id: user_id
      })
    end)
    |> Enum.map(&Repo.insert/1)
    |> Enum.reduce({:ok, []}, fn
      {:ok, participant}, {:ok, acc} -> {:ok, [participant | acc]}
      {:error, error}, _ -> {:error, error}
      _, {:error, error} -> {:error, error}
    end)
  end

  def get_conversation!(id) do
    Repo.get!(Conversation, id)
  end

  def list_user_conversations(user_id) do
    get_user_conversations(%User{id: user_id})
  end

  def list_conversation_participants(conversation_id) do
    ConversationParticipant
    |> where([p], p.conversation_id == ^conversation_id)
    |> preload(:user)
    |> Repo.all()
  end

  def get_conversation_between_users(user1_id, user2_id) do
    query =
      from c in Conversation,
        join: p1 in ConversationParticipant,
        on: p1.conversation_id == c.id and p1.user_id == ^user1_id,
        join: p2 in ConversationParticipant,
        on: p2.conversation_id == c.id and p2.user_id == ^user2_id,
        order_by: [desc: c.last_message_at, desc: c.id],
        limit: 1,
        preload: [conversation_participants: :user]

    Repo.one(query)
  end

  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  def get_user_conversations(%User{id: user_id}) do
    Conversation
    |> join(:inner, [c], p in ConversationParticipant, on: c.id == p.conversation_id)
    |> where([c, p], p.user_id == ^user_id)
    |> order_by([c, p], desc: c.last_message_at)
    |> preload(conversation_participants: :user)
    |> Repo.all()
  end

  def get_user_conversations_with_unread_counts(%User{id: user_id}) do
    # Optimized query that fetches conversations with unread counts in a single query
    # This eliminates N+1 queries when displaying conversation lists with unread badges
    query =
      from c in Conversation,
        join: p in ConversationParticipant,
        on: c.id == p.conversation_id and p.user_id == ^user_id,
        left_join: m in DirectMessage,
        on: m.conversation_id == c.id,
        left_join: p2 in ConversationParticipant,
        on: p2.conversation_id == c.id and p2.user_id == ^user_id,
        where:
          is_nil(p2.last_read_at) or
            (not is_nil(m.inserted_at) and m.inserted_at > p2.last_read_at),
        group_by: [c.id, p.id],
        order_by: [desc: c.last_message_at, desc: c.id],
        select: %{
          conversation: c,
          unread_count: count(m.id)
        },
        preload: [conversation_participants: :user]

    results = Repo.all(query)

    # Transform results into the expected format
    Enum.map(results, fn %{conversation: conversation, unread_count: unread_count} ->
      # Attach unread count to conversation for easy access
      Map.put(conversation, :unread_count, unread_count)
    end)
  end

  def get_conversation_with_unread_count(%User{id: user_id}, conversation_id) do
    # Single optimized query that fetches conversation with unread count
    query =
      from c in Conversation,
        join: p in ConversationParticipant,
        on: c.id == p.conversation_id and p.user_id == ^user_id,
        left_join: m in DirectMessage,
        on: m.conversation_id == c.id,
        left_join: p2 in ConversationParticipant,
        on: p2.conversation_id == c.id and p2.user_id == ^user_id,
        where: c.id == ^conversation_id,
        where:
          is_nil(p2.last_read_at) or
            (not is_nil(m.inserted_at) and m.inserted_at > p2.last_read_at),
        group_by: [c.id, p.id],
        select: %{
          conversation: c,
          unread_count: count(m.id)
        },
        preload: [conversation_participants: :user]

    case Repo.one(query) do
      nil -> nil
      %{conversation: conversation, unread_count: unread_count} -> {conversation, unread_count}
    end
  end

  def send_direct_message(%Conversation{} = conversation, attrs, %User{} = user) do
    # Check rate limit before sending
    case check_rate_limit(user.id, conversation.id) do
      :ok ->
        # Security check: Verify user is a participant in the conversation
        case get_conversation_participant(conversation.id, user.id) do
          nil ->
            {:error,
             %Ecto.Changeset{
               action: :insert,
               errors: [authorization: {"user is not a participant in this conversation", []}],
               data: %DirectMessage{},
               valid?: false
             }}

          _participant ->
            Repo.transaction(fn ->
              with {:ok, message} <-
                     %DirectMessage{}
                     |> DirectMessage.changeset(
                       Map.merge(attrs, %{conversation_id: conversation.id, user_id: user.id})
                     )
                     |> Repo.insert(),
                   {:ok, _} <- update_conversation_last_message(conversation, message.inserted_at) do
                message = message |> Repo.preload([:user, :attachments])
                broadcast_new_message(conversation, message)
                message
              else
                {:error, changeset} -> Repo.rollback(changeset)
              end
            end)
        end

      {:error, :rate_limited} ->
        {:error, "Message rate limit exceeded. Please wait before sending another message."}
    end
  end

  defp update_conversation_last_message(conversation, timestamp) do
    conversation
    |> Conversation.changeset(%{last_message_at: DateTime.truncate(timestamp, :second)})
    |> Repo.update()
  end

  defp broadcast_new_message(conversation, message) do
    # Rate limiting: Check if we're broadcasting too frequently
    topic = conversation_topic(conversation.id)

    # Add rate limiting metadata to the message
    enriched_message =
      Map.put(message, :broadcast_at, DateTime.utc_now() |> DateTime.truncate(:second))

    # Broadcast with error handling
    try do
      Phoenix.PubSub.broadcast!(
        @pubsub,
        topic,
        {:new_direct_message, enriched_message}
      )
    rescue
      error ->
        # Log broadcast failures but don't crash the message sending
        Logger.error("Failed to broadcast new message: #{inspect(error)}",
          conversation_id: conversation.id,
          message_id: message.id
        )
    end
  end

  def list_direct_messages(conversation_or_id, opts \\ [])

  def list_direct_messages(%Conversation{} = conversation, opts) do
    list_direct_messages(conversation.id, opts)
  end

  def list_direct_messages(conversation_id, opts) when is_integer(conversation_id) do
    # Authorization check: ensure user is a participant
    user_id = Keyword.get(opts, :current_user_id)

    if user_id && get_conversation_participant(conversation_id, user_id) do
      limit = Keyword.get(opts, :limit, @default_message_limit)
      cursor_before = Keyword.get(opts, :before)
      cursor_after = Keyword.get(opts, :after)

      query =
        DirectMessage
        |> where([m], m.conversation_id == ^conversation_id)
        |> order_by([m], desc: :inserted_at, asc: :id)
        |> preload([:user, :attachments])
        |> preload_reactions()
        |> limit(^limit)

      # Apply cursor-based pagination
      query =
        cond do
          cursor_after ->
            # Get messages after the cursor (newer messages)
            cursor_message = Repo.get!(DirectMessage, cursor_after)

            query
            |> where([m], m.inserted_at > ^cursor_message.inserted_at)
            |> or_where(
              [m],
              m.inserted_at == ^cursor_message.inserted_at and m.id > ^cursor_message.id
            )

          cursor_before ->
            # Get messages before the cursor (older messages)
            cursor_message = Repo.get!(DirectMessage, cursor_before)

            query
            |> where([m], m.inserted_at < ^cursor_message.inserted_at)
            |> or_where(
              [m],
              m.inserted_at == ^cursor_message.inserted_at and m.id < ^cursor_message.id
            )

          true ->
            # No cursor, get latest messages
            query
        end

      Repo.all(query)
    else
      []
    end
  end

  defp preload_reactions(message_query) do
    reactions_query = from r in Reaction, order_by: [asc: :id]
    preload(message_query, reactions: ^reactions_query)
  end

  def mark_conversation_read(%Conversation{} = conversation, %User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Use atomic upsert to avoid race conditions
    # This ensures only one participant record exists per user-conversation pair
    case Repo.insert(
           %ConversationParticipant{
             conversation_id: conversation.id,
             user_id: user.id,
             last_read_at: now
           },
           on_conflict: [set: [last_read_at: now]],
           conflict_target: [:conversation_id, :user_id]
         ) do
      {:ok, participant} ->
        {:ok, participant}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def mark_conversation_as_read(conversation_id, user_id) do
    conversation = get_conversation!(conversation_id)
    user = Slap.Accounts.get_user!(user_id)
    mark_conversation_read(conversation, user)
  end

  def get_unread_conversation_count(%User{id: user_id}) do
    query =
      from c in Conversation,
        join: p in ConversationParticipant,
        on: c.id == p.conversation_id,
        where: p.user_id == ^user_id,
        left_join: m in DirectMessage,
        on: m.conversation_id == c.id,
        left_join: p2 in ConversationParticipant,
        on: p2.conversation_id == c.id and p2.user_id == ^user_id,
        where: is_nil(p2.last_read_at) or m.inserted_at > p2.last_read_at,
        select: fragment("COUNT(DISTINCT ?)", c.id)

    Repo.one(query) || 0
  end

  def search_direct_messages(conversation_id, query, opts \\ []) do
    # Authorization check: ensure user is a participant
    user_id = Keyword.get(opts, :current_user_id)

    if user_id && get_conversation_participant(conversation_id, user_id) do
      limit = Keyword.get(opts, :limit, @default_message_limit)

      # Use PostgreSQL full-text search for better performance and relevance
      cursor_before = Keyword.get(opts, :before)
      cursor_after = Keyword.get(opts, :after)

      base_query =
        DirectMessage
        |> where([m], m.conversation_id == ^conversation_id)
        |> order_by([m], desc: :inserted_at, asc: :id)
        |> preload([:user, :attachments])
        |> preload_reactions()
        |> limit(^limit)

      # Apply cursor-based pagination
      base_query =
        cond do
          cursor_after ->
            # Get messages after the cursor (newer messages)
            cursor_message = Repo.get!(DirectMessage, cursor_after)

            base_query
            |> where([m], m.inserted_at > ^cursor_message.inserted_at)
            |> or_where(
              [m],
              m.inserted_at == ^cursor_message.inserted_at and m.id > ^cursor_message.id
            )

          cursor_before ->
            # Get messages before the cursor (older messages)
            cursor_message = Repo.get!(DirectMessage, cursor_before)

            base_query
            |> where([m], m.inserted_at < ^cursor_message.inserted_at)
            |> or_where(
              [m],
              m.inserted_at == ^cursor_message.inserted_at and m.id < ^cursor_message.id
            )

          true ->
            base_query
        end

      if query in [nil, ""] do
        # Return all messages if no search query
        Repo.all(base_query)
      else
        # Use full-text search with plainto_tsquery for better compatibility
        search_query = String.trim(query)

        # For special characters, fall back to simple LIKE search
        if String.match?(search_query, ~r/[&@#$%]/) do
          base_query
          |> where([m], like(m.body, ^"%#{search_query}%"))
          |> Repo.all()
        else
          # Use full-text search for regular text
          base_query
          |> where(
            [m],
            fragment(
              "to_tsvector('english', body) @@ plainto_tsquery('english', ?)",
              ^search_query
            )
          )
          |> order_by([m],
            desc:
              fragment(
                "ts_rank(to_tsvector('english', body), plainto_tsquery('english', ?))",
                ^search_query
              )
          )
          |> Repo.all()
        end
      end
    else
      []
    end
  end

  def get_direct_message!(id, opts \\ []) do
    message =
      DirectMessage
      |> Repo.get!(id)
      |> Repo.preload([:user, :attachments, :reactions])

    # Authorization check: ensure user is a participant in the conversation
    user_id = Keyword.get(opts, :current_user_id)

    if user_id && get_conversation_participant(message.conversation_id, user_id) do
      message
    else
      raise Ecto.NoResultsError, queryable: DirectMessage
    end
  end

  def update_direct_message(%DirectMessage{} = direct_message, attrs, %User{} = user) do
    # Authorization check: ensure user owns the message
    if direct_message.user_id == user.id do
      result =
        direct_message
        |> DirectMessage.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, updated_message} ->
          # Broadcast with error handling
          try do
            Phoenix.PubSub.broadcast!(
              @pubsub,
              conversation_topic(updated_message.conversation_id),
              {:updated_direct_message, updated_message}
            )
          rescue
            error ->
              Logger.error("Failed to broadcast message update: #{inspect(error)}",
                message_id: updated_message.id
              )
          end

          result

        {:error, _} ->
          result
      end
    else
      {:error,
       %Ecto.Changeset{
         action: :update,
         errors: [authorization: {"user does not own this message", []}],
         data: direct_message,
         valid?: false
       }}
    end
  end

  def delete_direct_message(%DirectMessage{} = direct_message) do
    Repo.transaction(fn ->
      direct_message = direct_message |> Repo.preload(:attachments)

      Enum.each(direct_message.attachments, fn attachment ->
        Uploads.delete_file(attachment.file_path)
      end)

      {:ok, deleted_message} = Repo.delete(direct_message)

      # Broadcast with error handling
      try do
        Phoenix.PubSub.broadcast!(
          @pubsub,
          conversation_topic(direct_message.conversation_id),
          {:deleted_direct_message, deleted_message}
        )
      rescue
        error ->
          Logger.error("Failed to broadcast message deletion: #{inspect(error)}",
            message_id: deleted_message.id
          )
      end

      deleted_message
    end)
  end

  def delete_conversation(%Conversation{} = conversation) do
    # Broadcast deletion event to all participants before actual deletion
    Phoenix.PubSub.broadcast!(
      @pubsub,
      conversation_topic(conversation.id),
      {:conversation_deleted, conversation.id}
    )

    # Delete conversation and participants (cascade will handle participants)
    Repo.delete(conversation)
  end

  def add_participant_to_conversation(%Conversation{} = conversation, user_id) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_id: conversation.id,
      user_id: user_id
    })
    |> Repo.insert()
  end

  def remove_participant_from_conversation(%Conversation{} = conversation, user_id) do
    ConversationParticipant
    |> where([p], p.conversation_id == ^conversation.id and p.user_id == ^user_id)
    |> Repo.delete_all()
  end

  def get_conversation_participant(conversation_id, user_id) do
    ConversationParticipant
    |> where([p], p.conversation_id == ^conversation_id and p.user_id == ^user_id)
    |> Repo.one()
  end

  def count_unread_messages(conversation_id, user_id) do
    participant = get_conversation_participant(conversation_id, user_id)

    if participant do
      query =
        from m in DirectMessage,
          where: m.conversation_id == ^conversation_id,
          where: m.inserted_at > ^participant.last_read_at,
          select: count(m.id)

      Repo.one(query) || 0
    else
      # If no participant record exists, count all messages as unread
      query =
        from m in DirectMessage,
          where: m.conversation_id == ^conversation_id,
          select: count(m.id)

      Repo.one(query) || 0
    end
  end

  def get_messages_since(conversation_id, last_message_id, opts \\ []) do
    # Authorization check: ensure user is a participant
    user_id = Keyword.get(opts, :current_user_id)

    if user_id && get_conversation_participant(conversation_id, user_id) do
      limit = Keyword.get(opts, :limit, @default_message_limit)

      query =
        from m in DirectMessage,
          where: m.conversation_id == ^conversation_id,
          where: m.id > ^last_message_id,
          order_by: [asc: :inserted_at, asc: :id],
          limit: ^limit

      query
      |> preload([:user, :attachments])
      |> preload_reactions()
      |> Repo.all()
    else
      []
    end
  end

  def delete_direct_message(message_id, %User{id: user_id}) do
    case Repo.get(DirectMessage, message_id) do
      %DirectMessage{user_id: ^user_id, conversation_id: conversation_id} = message ->
        # Security check: Verify user is still a participant in the conversation
        case get_conversation_participant(conversation_id, user_id) do
          nil ->
            {:error,
             %Ecto.Changeset{
               action: :delete,
               errors: [authorization: {"user is not a participant in this conversation", []}],
               data: message,
               valid?: false
             }}

          _participant ->
            message = message |> Repo.preload(:attachments)

            Repo.transaction(fn ->
              Enum.each(message.attachments, fn attachment ->
                Uploads.delete_file(attachment.file_path)
              end)

              {:ok, deleted_message} = Repo.delete(message)

              # Broadcast with error handling
              try do
                Phoenix.PubSub.broadcast!(
                  @pubsub,
                  conversation_topic(message.conversation_id),
                  {:direct_message_deleted, deleted_message}
                )
              rescue
                error ->
                  Logger.error("Failed to broadcast message deletion: #{inspect(error)}",
                    message_id: deleted_message.id
                  )
              end

              deleted_message
            end)
        end

      _ ->
        {:error,
         %Ecto.Changeset{
           action: :delete,
           errors: [message: {"message not found or access denied", []}],
           data: %DirectMessage{},
           valid?: false
         }}
    end
  end

  defp check_rate_limit(user_id, conversation_id) do
    # Simple in-memory rate limiting using ETS
    # In production, consider using Redis or similar for distributed rate limiting
    table_name = :rate_limit_table

    # Create ETS table if it doesn't exist
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:set, :public, :named_table])

      _ ->
        :ok
    end

    key = {user_id, conversation_id}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(table_name, key) do
      [{^key, count, window_start}] when now - window_start < @rate_limit_window ->
        if count >= @rate_limit_max_messages do
          {:error, :rate_limited}
        else
          :ets.update_element(table_name, key, {2, count + 1})
          :ok
        end

      _ ->
        # First message in window or window expired
        :ets.insert(table_name, {key, 1, now})
        :ok
    end
  end
end
