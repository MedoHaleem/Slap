defmodule Slap.DirectMessaging do
  alias Slap.Accounts.User
  alias Slap.Chat.{Conversation, DirectMessage, ConversationParticipant, Reaction}
  alias Slap.{Repo, Uploads}
  import Ecto.Query

  @pubsub Slap.PubSub

  def subscribe_to_conversation(conversation) do
    Phoenix.PubSub.subscribe(@pubsub, conversation_topic(conversation.id))
  end

  def unsubscribe_from_conversation(conversation) do
    Phoenix.PubSub.unsubscribe(@pubsub, conversation_topic(conversation.id))
  end

  defp conversation_topic(conversation_id), do: "conversation:#{conversation_id}"

  def create_conversation(%User{} = creator, [%User{} = _participant | _] = participants) do
    participants = [creator | participants] |> Enum.uniq_by(& &1.id)

    Repo.transaction(fn ->
      with {:ok, conversation} <-
             %Conversation{}
             |> Conversation.changeset(%{})
             |> Repo.insert(),
           {:ok, _} <- add_participants_to_conversation(conversation, participants) do
        conversation
      end
    end)
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

  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def create_conversation_with_participants(attrs \\ %{}, participant_ids)
      when is_list(participant_ids) do
    if Enum.empty?(participant_ids) do
      {:error,
       %Ecto.Changeset{
         action: :insert,
         errors: [participants: {"can't be empty", []}],
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
          # Preload the conversation_participants association
          conversation |> Repo.preload(conversation_participants: :user)
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
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

  def get_conversation_with_unread_count(%User{id: user_id}, conversation_id) do
    # First get the conversation with participants preloaded
    conversation_query =
      from c in Conversation,
        join: p in ConversationParticipant,
        on: c.id == p.conversation_id,
        where: p.user_id == ^user_id and c.id == ^conversation_id,
        preload: [conversation_participants: :user]

    conversation = Repo.one(conversation_query)

    if conversation do
      # Now get the unread count
      unread_query =
        from m in DirectMessage,
          join: p in ConversationParticipant,
          on: p.conversation_id == m.conversation_id,
          left_join: p2 in ConversationParticipant,
          on: p2.conversation_id == m.conversation_id and p2.user_id == ^user_id,
          where:
            m.conversation_id == ^conversation_id and
              p.user_id == ^user_id and
              (is_nil(p2.last_read_at) or m.inserted_at > p2.last_read_at),
          select: count(m.id)

      unread_count = Repo.one(unread_query) || 0
      {conversation, unread_count}
    else
      nil
    end
  end

  def send_direct_message(%Conversation{} = conversation, attrs, %User{} = user) do
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
    |> Conversation.changeset(%{last_message_at: timestamp})
    |> Repo.update()
  end

  defp broadcast_new_message(conversation, message) do
    Phoenix.PubSub.broadcast!(
      @pubsub,
      conversation_topic(conversation.id),
      {:new_direct_message, message}
    )
  end

  def list_direct_messages(conversation_or_id, opts \\ [])

  def list_direct_messages(%Conversation{} = conversation, opts) do
    list_direct_messages(conversation.id, opts)
  end

  def list_direct_messages(conversation_id, _opts) when is_integer(conversation_id) do
    DirectMessage
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], desc: :inserted_at, asc: :id)
    |> preload([:user, :attachments])
    |> preload_reactions()
    |> limit(50)
    |> Repo.all()
  end

  defp preload_reactions(message_query) do
    reactions_query = from r in Reaction, order_by: [asc: :id]
    preload(message_query, reactions: ^reactions_query)
  end

  def mark_conversation_read(%Conversation{} = conversation, %User{} = user) do
    now = DateTime.utc_now()

    # First try to update existing participant
    {count, _} =
      ConversationParticipant
      |> where([p], p.conversation_id == ^conversation.id and p.user_id == ^user.id)
      |> Repo.update_all(set: [last_read_at: now])

    if count == 0 do
      # If no participant exists, create one
      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: now
      })
      |> Repo.insert()
    else
      # Return the updated participant
      participant =
        ConversationParticipant
        |> where([p], p.conversation_id == ^conversation.id and p.user_id == ^user.id)
        |> Repo.one!()

      {:ok, participant}
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
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    # Use ILIKE for case-insensitive search instead of full-text search for simplicity
    search_pattern = if query in [nil, ""], do: "%", else: "%#{query}%"

    DirectMessage
    |> where([m], m.conversation_id == ^conversation_id)
    |> where([m], ilike(m.body, ^search_pattern))
    |> preload([:user, :attachments])
    |> preload_reactions()
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([m], desc: :inserted_at)
    |> Repo.all()
  end

  def get_direct_message!(id) do
    DirectMessage
    |> Repo.get!(id)
    |> Repo.preload([:user, :attachments, :reactions])
  end

  def update_direct_message(%DirectMessage{} = direct_message, attrs) do
    result =
      direct_message
      |> DirectMessage.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_message} ->
        Phoenix.PubSub.broadcast!(
          @pubsub,
          conversation_topic(updated_message.conversation_id),
          {:updated_direct_message, updated_message}
        )

        result

      {:error, _} ->
        result
    end
  end

  def delete_direct_message(%DirectMessage{} = direct_message) do
    Repo.transaction(fn ->
      direct_message = direct_message |> Repo.preload(:attachments)

      Enum.each(direct_message.attachments, fn attachment ->
        Uploads.delete_file(attachment.file_path)
      end)

      {:ok, deleted_message} = Repo.delete(direct_message)

      Phoenix.PubSub.broadcast!(
        @pubsub,
        conversation_topic(direct_message.conversation_id),
        {:deleted_direct_message, deleted_message}
      )

      deleted_message
    end)
  end

  def delete_conversation(%Conversation{} = conversation) do
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

  def delete_direct_message(message_id, %User{id: user_id}) do
    case Repo.get(DirectMessage, message_id) do
      %DirectMessage{user_id: ^user_id} = message ->
        message = message |> Repo.preload(:attachments)

        Enum.each(message.attachments, fn attachment ->
          Uploads.delete_file(attachment.file_path)
        end)

        {:ok, deleted_message} = Repo.delete(message)

        Phoenix.PubSub.broadcast!(
          @pubsub,
          conversation_topic(message.conversation_id),
          {:direct_message_deleted, deleted_message}
        )

        deleted_message

      _ ->
        {:error, :not_found}
    end
  end
end
