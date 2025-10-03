defmodule Slap.DirectMessaging do
  alias Slap.Accounts.User

  alias Slap.Chat.{
    Conversation,
    DirectMessage,
    ConversationParticipant,
    ConversationSetting,
    ConversationInvite,
    Reaction
  }

  alias Slap.{Repo, Uploads, Constants, Authorization, RateLimiter, ErrorHandler, QueryBuilder}
  import Ecto.Query
  require Logger

  @pubsub Slap.PubSub

  # Configuration constants
  @default_message_limit Constants.default_message_limit()
  # 1 minute window
  # Note: Rate limiting is now handled by Slap.RateLimiter module

  # Group conversation constants
  @max_participants Constants.max_participants()

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
    conversation_type = Map.get(attrs, "type") || Map.get(attrs, :type) || "direct"

    # Validate that we don't have conflicting participant specifications
    create_conversation_with_validation(
      attrs,
      participants,
      participant_ids,
      creator,
      conversation_type
    )
  end

  # Extract the conversation creation logic with validation
  defp create_conversation_with_validation(
         attrs,
         participants,
         participant_ids,
         creator,
         conversation_type
       ) do
    cond do
      participants != [] and participant_ids != [] ->
        {:error,
         %Ecto.Changeset{
           errors: [participants: {"cannot specify both participants and participant_ids", []}],
           valid?: false
         }}

      participants == [] and participant_ids == [] ->
        # Check if this was called from create_conversation_with_participants with empty list
        if Map.has_key?(attrs, :_called_with_participants) do
          {:error,
           %Ecto.Changeset{
             errors: [participants: {"must have at least 2 participants", []}],
             valid?: false
           }}
        else
          # Simple conversation creation without participants
          create_simple_conversation(attrs)
        end

      participants != [] ->
        # Create conversation with user structs
        create_conversation_with_users(attrs, participants, creator, conversation_type)

      participant_ids != [] ->
        # Create conversation with user IDs
        create_conversation_with_ids(attrs, participant_ids, conversation_type)
    end
  end

  # Extract simple conversation creation logic
  defp create_simple_conversation(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def create_group_conversation(attrs \\ %{}, participants, creator) do
    # Ensure type is set to group
    group_attrs = Map.merge(attrs, %{type: "group", is_public: Map.get(attrs, :is_public, false)})

    create_conversation(group_attrs, participants: participants, creator: creator)
  end

  def create_direct_message_conversation(attrs \\ %{}, user1, user2) do
    # Ensure type is set to direct
    dm_attrs = Map.merge(attrs, %{type: "direct"})

    create_conversation(dm_attrs, participants: [user1, user2])
  end

  # Legacy function for backward compatibility
  def create_conversation_with_participants(attrs \\ %{}, participant_ids)
      when is_list(participant_ids) do
    # Mark that this was called with participants to enable validation
    marked_attrs = Map.put(attrs, :_called_with_participants, true)
    create_conversation(marked_attrs, participant_ids: participant_ids)
  end

  defp create_conversation_with_users(attrs, participants, creator, conversation_type) do
    # Include creator in participants if provided
    all_participants = prepare_participants_list(participants, creator)

    # Validate participant limits based on conversation type
    participant_count = length(all_participants)

    case validate_participant_limits(conversation_type, participant_count) do
      {:error, reason} ->
        {:error, %Ecto.Changeset{errors: [participants: {reason, []}], valid?: false}}

      :ok ->
        create_conversation_with_participants(attrs, all_participants, creator, conversation_type)
    end
  end

  # Extract participant list preparation logic
  defp prepare_participants_list(participants, creator) do
    if creator do
      [creator | participants] |> Enum.uniq_by(& &1.id)
    else
      participants |> Enum.uniq_by(& &1.id)
    end
  end

  # Extract conversation creation with participants logic
  defp create_conversation_with_participants(attrs, participants, creator, conversation_type) do
    Repo.transaction(fn ->
      with {:ok, conversation} <-
             %Conversation{}
             |> Conversation.changeset(attrs)
             |> Repo.insert(),
           {:ok, _} <- add_participants_to_conversation(conversation, participants, creator) do
        # Create default settings for the conversation
        {:ok, _} = create_conversation_settings(conversation, conversation_type)

        conversation |> Repo.preload(conversation_participants: :user)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_conversation_with_ids(attrs, participant_ids, conversation_type) do
    participant_ids = Enum.uniq(participant_ids)

    # Validate participant limits based on conversation type
    participant_count = length(participant_ids)

    case validate_participant_limits(conversation_type, participant_count) do
      {:error, reason} ->
        {:error, %Ecto.Changeset{errors: [participants: {reason, []}], valid?: false}}

      :ok ->
        create_conversation_with_participant_ids(attrs, participant_ids, conversation_type)
    end
  end

  # Extract conversation creation with participant IDs logic
  defp create_conversation_with_participant_ids(attrs, participant_ids, conversation_type) do
    Repo.transaction(fn ->
      with {:ok, conversation} <-
             %Conversation{}
             |> Conversation.changeset(attrs)
             |> Repo.insert(),
           {:ok, _} <- add_participant_ids_to_conversation(conversation, participant_ids) do
        # Create default settings for the conversation
        {:ok, _} = create_conversation_settings(conversation, conversation_type)

        conversation |> Repo.preload(conversation_participants: :user)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp validate_participant_limits("direct", count) when count > 2 do
    {:error, "direct conversations can have maximum 2 participants"}
  end

  defp validate_participant_limits("direct", count) when count < 2 do
    {:error, "must have at least 2 participants"}
  end

  defp validate_participant_limits("group", count) when count < 2 do
    {:error, "must have at least 2 participants"}
  end

  defp validate_participant_limits("group", count) when count > @max_participants do
    {:error, "group conversations can have maximum #{@max_participants} participants"}
  end

  defp validate_participant_limits(_type, count) when count < 2 do
    {:error, "must have at least 2 participants"}
  end

  defp validate_participant_limits(_type, _count), do: :ok

  defp create_conversation_settings(conversation, conversation_type) do
    settings_attrs = %{
      conversation_id: conversation.id,
      allow_participant_invites: conversation_type != "direct",
      require_admin_approval: conversation_type == "group",
      message_editing_enabled: true,
      file_sharing_enabled: true,
      max_participants: if(conversation_type == "direct", do: 2, else: 100)
    }

    %ConversationSetting{}
    |> ConversationSetting.changeset(settings_attrs)
    |> Repo.insert()
  end

  defp add_participants_to_conversation(conversation, participants, creator) do
    participants
    |> Enum.map(fn user ->
      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        role: determine_participant_role(conversation, user, creator),
        can_invite: can_participant_invite(conversation, user, creator)
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
        user_id: user_id,
        # Default role for ID-based addition
        role: "member",
        can_invite: conversation.type != "direct"
      })
    end)
    |> Enum.map(&Repo.insert/1)
    |> Enum.reduce({:ok, []}, fn
      {:ok, participant}, {:ok, acc} -> {:ok, [participant | acc]}
      {:error, error}, _ -> {:error, error}
      _, {:error, error} -> {:error, error}
    end)
  end

  defp determine_participant_role(conversation, user, creator) do
    cond do
      conversation.type == "direct" -> "member"
      creator && user.id == creator.id -> "admin"
      true -> "member"
    end
  end

  defp can_participant_invite(conversation, user, creator) do
    conversation.type != "direct" && (creator == nil || user.id != creator.id)
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
    case RateLimiter.check_rate_limit({user.id, conversation.id}, :send_message) do
      :ok ->
        # Security check: Verify user is a participant in the conversation
        case get_conversation_participant(conversation.id, user.id) do
          nil ->
            {:error,
             %Ecto.Changeset{errors: [authorization: {"Not authorized", []}], valid?: false}}

          _participant ->
            create_message_with_broadcast(conversation, attrs, user)
        end

      {:error, :rate_limited} ->
        {:error,
         %Ecto.Changeset{errors: [rate_limit: {"Rate limit exceeded", []}], valid?: false}}
    end
  end

  # Extract the message creation and broadcasting logic to a separate function
  defp create_message_with_broadcast(conversation, attrs, user) do
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

  defp update_conversation_last_message(conversation, timestamp) do
    conversation
    |> Conversation.changeset(%{last_message_at: DateTime.truncate(timestamp, :second)})
    |> Repo.update()
  end

  defp broadcast_new_message(conversation, message) do
    topic = Constants.pubsub_topic(:conversation, conversation.id)

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
      # Use QueryBuilder to build the query
      base_query =
        QueryBuilder.messages_query(
          schema: DirectMessage,
          conversation_id: conversation_id,
          include_reactions: true,
          include_attachments: true
        )

      # Apply cursor-based pagination
      result = QueryBuilder.cursor_paginate_query(base_query, opts)

      # Execute the query and return the entries directly for backward compatibility
      case result do
        query when is_struct(query, Ecto.Query) ->
          # Execute the query and return the results
          Repo.all(query)

        _ ->
          # Handle any other case
          []
      end
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
      # Build a simple search query for now to avoid PostgreSQL issues
      base_query =
        from m in DirectMessage,
          where: m.conversation_id == ^conversation_id,
          preload: [:user, :attachments, reactions: ^from(r in Reaction, order_by: [asc: r.id])]

      # Apply search filter if query is provided
      search_query =
        if query && query != "" do
          # Use simple LIKE search for now to avoid PostgreSQL full-text search issues
          where(base_query, [m], ilike(m.body, ^"%#{query}%"))
        else
          base_query
        end

      # Apply ordering
      ordered_query = order_by(search_query, [m], desc: m.inserted_at, asc: m.id)

      # Apply limit if provided
      limited_query =
        case Keyword.get(opts, :limit) do
          nil -> ordered_query
          limit -> limit(ordered_query, ^limit)
        end

      # Execute the query
      Repo.all(limited_query)
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

  # The check_rate_limit function has been replaced with calls to Slap.RateLimiter

  ## Group Conversation Management Functions

  @doc """
  Gets the conversation settings.
  """
  def get_conversation_settings(%Conversation{id: conversation_id}) do
    case Repo.get_by(ConversationSetting, conversation_id: conversation_id) do
      nil ->
        # Create default settings if they don't exist
        create_default_conversation_settings(conversation_id)

      settings ->
        {:ok, settings}
    end
  end

  defp create_default_conversation_settings(conversation_id) do
    settings_attrs = %{
      conversation_id: conversation_id,
      allow_participant_invites: true,
      require_admin_approval: false,
      message_editing_enabled: true,
      file_sharing_enabled: true,
      max_participants: 100
    }

    %ConversationSetting{}
    |> ConversationSetting.changeset(settings_attrs)
    |> Repo.insert()
  end

  @doc """
  Updates conversation settings. Only admins and moderators can update settings.
  """
  def update_conversation_settings(
        %Conversation{} = conversation,
        attrs,
        %User{id: _user_id} = user
      ) do
    if Authorization.can_manage_conversation?(user, conversation) do
      case get_conversation_settings(conversation) do
        {:ok, settings} ->
          settings
          |> ConversationSetting.changeset(attrs)
          |> Repo.update()

        {:error, _reason} = error ->
          error
      end
    else
      {:error, "Insufficient permissions to update conversation settings"}
    end
  end

  @doc """
  Gets the user's role in a conversation.
  """
  def get_user_role_in_conversation(conversation_id, user_id) do
    case get_conversation_participant(conversation_id, user_id) do
      nil -> {:error, "User is not a participant in this conversation"}
      participant -> {:ok, participant.role}
    end
  end

  @doc """
  Checks if a user has a specific permission in a conversation.
  """
  def user_has_permission?(conversation_id, user_id, permission) do
    case get_conversation!(conversation_id) do
      nil ->
        false

      conversation ->
        Authorization.can_access_conversation?(%User{id: user_id}, conversation, permission)
    end
  end

  @doc """
  Promotes a participant to a higher role. Only admins can promote participants.
  """
  def promote_participant(
        %Conversation{id: conversation_id} = conversation,
        target_user_id,
        new_role,
        %User{id: _user_id} = user
      ) do
    if Authorization.can_manage_participants?(user, conversation) do
      case get_conversation_participant(conversation_id, target_user_id) do
        nil ->
          {:error, "Participant not found"}

        target_participant ->
          case Authorization.validate_role_promotion(target_participant.role, new_role) do
            :ok ->
              target_participant
              |> ConversationParticipant.changeset(%{role: new_role})
              |> Repo.update()

            {:error, reason} ->
              {:error, reason}
          end
      end
    else
      {:error, "Only admins can promote participants"}
    end
  end

  @doc """
  Creates an invitation for a user to join a conversation.
  """
  def create_conversation_invite(
        %Conversation{id: conversation_id} = conversation,
        invitee_id,
        %User{id: inviter_id} = inviter
      ) do
    if Authorization.can_invite_to_conversation?(inviter, conversation) do
      case get_conversation_settings(conversation) do
        {:ok, _settings} ->
          case validate_user_not_already_participant(conversation_id, invitee_id) do
            {:ok, :not_participant} ->
              token = generate_invite_token()

              %ConversationInvite{}
              |> ConversationInvite.changeset(%{
                conversation_id: conversation_id,
                inviter_id: inviter_id,
                invitee_id: invitee_id,
                token: token
              })
              |> Repo.insert()

            {:error, reason} ->
              ErrorHandler.error_with_message(reason)
          end

        {:error, _reason} = error ->
          error
      end
    else
      ErrorHandler.authorization_error()
    end
  end

  # defp validate_invite_permissions(settings, inviter_role) do
  #   cond do
  #     settings.allow_participant_invites -> :ok
  #     inviter_role in ["admin", "moderator"] -> :ok
  #     true -> {:error, "Invitations are disabled for this conversation"}
  #   end
  # end

  defp validate_user_not_already_participant(conversation_id, user_id) do
    case get_conversation_participant(conversation_id, user_id) do
      nil -> {:ok, :not_participant}
      _participant -> {:error, "User is already a participant in this conversation"}
    end
  end

  defp generate_invite_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 32)
  end

  @doc """
  Accepts a conversation invitation using a token.
  """
  def accept_conversation_invite(token, %User{id: user_id}) do
    case Repo.get_by(ConversationInvite, token: token, invitee_id: user_id, status: "pending") do
      nil ->
        {:error, "Invalid or expired invitation"}

      invite ->
        if DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt do
          # Expire the invite
          invite
          |> ConversationInvite.changeset(%{status: "expired"})
          |> Repo.update()

          {:error, "Invitation has expired"}
        else
          Repo.transaction(fn ->
            with {:ok, participant} <-
                   add_participant_to_conversation(
                     %Conversation{id: invite.conversation_id},
                     user_id
                   ),
                 {:ok, _} <-
                   invite
                   |> ConversationInvite.changeset(%{status: "accepted"})
                   |> Repo.update() do
              participant
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)
        end
    end
  end

  @doc """
  Gets pending invitations for a user.
  """
  def get_user_pending_invites(%User{id: user_id}) do
    ConversationInvite
    |> where([i], i.invitee_id == ^user_id and i.status == "pending")
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> preload([:conversation, :inviter])
    |> Repo.all()
  end

  @doc """
  Gets all conversations of a specific type for a user.
  """
  def list_user_conversations_by_type(%User{id: user_id}, conversation_type) do
    Conversation
    |> join(:inner, [c], p in ConversationParticipant, on: c.id == p.conversation_id)
    |> where([c, p], p.user_id == ^user_id and c.type == ^conversation_type)
    |> order_by([c, p], desc: c.last_message_at)
    |> preload(conversation_participants: :user)
    |> Repo.all()
  end

  @doc """
  Gets public groups that a user can join.
  """
  def list_public_groups(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Conversation
    |> join(:left, [c], p in ConversationParticipant,
      on: c.id == p.conversation_id and p.user_id == ^user_id
    )
    |> where([c, p], c.is_public == true and c.type == "group" and is_nil(p.id))
    |> order_by([c], desc: c.last_message_at)
    |> preload(conversation_participants: :user)
    |> limit(^limit)
    |> Repo.all()
  end
end
