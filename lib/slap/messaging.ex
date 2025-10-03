defmodule Slap.Messaging do
  @moduledoc """
  Unified messaging system for the Slap application.
  Provides common functionality for both room messages and direct messages.
  """

  alias Slap.Constants
  alias Slap.Pagination
  alias Slap.RateLimiter
  alias Slap.{Repo, Chat}
  alias Slap.Chat.{Message, DirectMessage, Reaction}
  alias Slap.Accounts.User
  import Ecto.Query

  @type message_type :: :room | :direct
  @type message :: %Message{} | %DirectMessage{}
  @type search_options :: [
          limit: non_neg_integer(),
          before: non_neg_integer(),
          after: non_neg_integer(),
          include_threads: boolean()
        ]

  @doc """
  Creates a message with unified rate limiting and broadcasting.

  ## Parameters
  - `type` - Either :room or :direct
  - `context` - Room for :room type, Conversation for :direct type
  - `attrs` - Message attributes
  - `user` - The user creating the message
  - `opts` - Additional options
  """
  @spec create_message(message_type(), any(), map(), %User{}, keyword()) ::
          {:ok, message()} | {:error, Ecto.Changeset.t() | String.t()}
  def create_message(type, context, attrs, user, opts \\ []) do
    # Check rate limit
    rate_limit_key = get_rate_limit_key(type, context, user)

    case RateLimiter.check_rate_limit(rate_limit_key, :send_message) do
      :ok ->
        do_create_message(type, context, attrs, user, opts)

      {:error, :rate_limited} ->
        {:error, Constants.get_error_message(:rate_limit_exceeded)}
    end
  end

  @doc """
  Lists messages with unified pagination.
  """
  @spec list_messages(message_type(), any(), keyword()) :: any()
  def list_messages(type, context, opts \\ []) do
    query = build_message_query(type, context)

    # Apply preloads
    query =
      query
      |> preload([:user, :attachments])
      |> preload_reactions()

    # Apply pagination
    Pagination.paginate(query, opts)
  end

  @doc """
  Searches messages with unified search functionality.
  """
  @spec search_messages(message_type(), any(), String.t(), search_options()) ::
          [message()] | {:error, String.t()}
  def search_messages(type, context, search_query, opts \\ []) do
    if not authorized_to_search?(type, context, Keyword.get(opts, :current_user)) do
      {:error, "Not authorized to search messages"}
    else
      limit = Keyword.get(opts, :limit, Constants.default_search_limit())
      cursor_before = Keyword.get(opts, :before)
      cursor_after = Keyword.get(opts, :after)
      include_threads = Keyword.get(opts, :include_threads, false)

      base_query = build_search_query(type, context, search_query, include_threads)

      # Apply cursor-based pagination
      query = apply_cursor_pagination(base_query, cursor_before, cursor_after)

      # Apply limit and preloads
      query =
        query
        |> limit(^limit)
        |> preload([:user, :attachments])
        |> preload_reactions()

      results = Repo.all(query)

      # Sort by relevance if search query is provided
      if is_binary(search_query) && search_query != "" do
        sort_by_relevance(results, search_query)
      else
        results
      end
    end
  end

  @doc """
  Gets a message with authorization check.
  """
  @spec get_message(message_type(), non_neg_integer(), %User{}) ::
          {:ok, message()} | {:error, String.t()}
  def get_message(type, message_id, user) do
    message = get_message_by_type(type, message_id)

    if authorized_to_view_message?(type, message, user) do
      {:ok, message}
    else
      {:error, "Message not found or access denied"}
    end
  end

  @doc """
  Updates a message with authorization check.
  """
  @spec update_message(message_type(), message(), map(), User.t()) ::
          {:ok, message()} | {:error, Ecto.Changeset.t() | String.t()}
  def update_message(type, message, attrs, user) do
    if authorized_to_update_message?(type, message, user) do
      result = do_update_message(type, message, attrs)

      case result do
        {:ok, updated_message} ->
          broadcast_message_update(type, updated_message)
          result

        {:error, _} = error ->
          error
      end
    else
      {:error, "Not authorized to update this message"}
    end
  end

  @doc """
  Deletes a message with authorization check.
  """
  @spec delete_message(message_type(), message(), User.t()) ::
          {:ok, message()} | {:error, String.t()}
  def delete_message(type, message, user) do
    if authorized_to_delete_message?(type, message, user) do
      result = do_delete_message(type, message)

      case result do
        {:ok, deleted_message} ->
          broadcast_message_deletion(type, deleted_message)
          result

        {:error, _} = error ->
          error
      end
    else
      {:error, "Not authorized to delete this message"}
    end
  end

  @doc """
  Adds a reaction to a message.
  """
  @spec add_reaction(message_type(), message(), String.t(), User.t()) ::
          {:ok, Reaction.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def add_reaction(type, message, emoji, user) do
    if authorized_to_react_to_message?(type, message, user) do
      result = do_add_reaction(type, message, emoji, user)

      case result do
        {:ok, reaction} ->
          broadcast_reaction_update(type, :added, reaction)
          result

        {:error, _} = error ->
          error
      end
    else
      {:error, "Not authorized to react to this message"}
    end
  end

  @doc """
  Removes a reaction from a message.
  """
  @spec remove_reaction(message_type(), message(), String.t(), User.t()) ::
          {:ok, Reaction.t()} | {:error, String.t()}
  def remove_reaction(type, message, emoji, user) do
    if authorized_to_react_to_message?(type, message, user) do
      result = do_remove_reaction(type, message, emoji, user)

      case result do
        {:ok, reaction} ->
          broadcast_reaction_update(type, :removed, reaction)
          result

        {:error, _} = error ->
          error
      end
    else
      {:error, "Not authorized to react to this message"}
    end
  end

  @doc """
  Gets unread message count for a user in a context.
  """
  @spec get_unread_count(message_type(), any(), User.t()) :: non_neg_integer()
  def get_unread_count(type, context, user) do
    case type do
      :room ->
        Chat.unread_message_count(context, user)

      :direct ->
        Chat.DirectMessaging.count_unread_messages(context.id, user.id)
    end
  end

  @doc """
  Marks messages as read for a user in a context.
  """
  @spec mark_as_read(message_type(), any(), User.t()) :: :ok | {:error, String.t()}
  def mark_as_read(type, context, user) do
    case type do
      :room ->
        Chat.update_last_read_id(context, user)
        :ok

      :direct ->
        case Chat.DirectMessaging.mark_conversation_read(context, user) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, "Failed to mark as read"}
        end
    end
  end

  @doc """
  Broadcasts a new message to the appropriate topic.
  """
  @spec broadcast_new_message(message_type(), message()) :: :ok
  def broadcast_new_message(type, message) do
    topic = get_broadcast_topic(type, get_context_id(type, message))

    Phoenix.PubSub.broadcast!(
      Slap.PubSub,
      topic,
      {get_broadcast_event(type, :new), message}
    )

    :ok
  end

  @doc """
  Broadcasts a message update to the appropriate topic.
  """
  @spec broadcast_message_update(message_type(), message()) :: :ok
  def broadcast_message_update(type, message) do
    topic = get_broadcast_topic(type, get_context_id(type, message))

    Phoenix.PubSub.broadcast!(
      Slap.PubSub,
      topic,
      {get_broadcast_event(type, :updated), message}
    )

    :ok
  end

  @doc """
  Broadcasts a message deletion to the appropriate topic.
  """
  @spec broadcast_message_deletion(message_type(), message()) :: :ok
  def broadcast_message_deletion(type, message) do
    topic = get_broadcast_topic(type, get_context_id(type, message))

    Phoenix.PubSub.broadcast!(
      Slap.PubSub,
      topic,
      {get_broadcast_event(type, :deleted), message}
    )

    :ok
  end

  # Private functions

  defp get_rate_limit_key(:room, room, user), do: {user.id, room.id}
  defp get_rate_limit_key(:direct, conversation, user), do: {user.id, conversation.id}

  defp do_create_message(:room, room, attrs, user, _opts) do
    Chat.create_message(room, attrs, user)
  end

  defp do_create_message(:direct, conversation, attrs, user, _opts) do
    Chat.DirectMessaging.send_direct_message(conversation, attrs, user)
  end

  defp build_message_query(:room, room) do
    from m in Message,
      where: m.room_id == ^room.id,
      order_by: [desc: m.inserted_at, asc: m.id]
  end

  defp build_message_query(:direct, conversation) do
    from m in DirectMessage,
      where: m.conversation_id == ^conversation.id,
      order_by: [desc: m.inserted_at, asc: m.id]
  end

  defp build_search_query(:room, room, query, include_threads) do
    base_query =
      from m in Message,
        where: m.room_id == ^room.id,
        order_by: [desc: m.inserted_at, asc: m.id]

    if include_threads do
      # Include replies in search
      from m in Message,
        where: m.room_id == ^room.id,
        or_where:
          fragment(
            "EXISTS (SELECT 1 FROM replies r WHERE r.message_id = ? AND to_tsvector('english', r.body) @@ plainto_tsquery('english', ?))",
            m.id,
            ^query
          ),
        order_by: [desc: m.inserted_at, asc: m.id]
    else
      base_query
    end
  end

  defp build_search_query(:direct, conversation, _query, _include_threads) do
    from m in DirectMessage,
      where: m.conversation_id == ^conversation.id,
      order_by: [desc: m.inserted_at, asc: m.id]
  end

  defp apply_cursor_pagination(query, nil, nil), do: query

  defp apply_cursor_pagination(query, cursor_before, nil),
    do: apply_before_cursor(query, cursor_before)

  defp apply_cursor_pagination(query, nil, cursor_after),
    do: apply_after_cursor(query, cursor_after)

  defp apply_before_cursor(query, cursor_id) do
    cursor_message = get_cursor_message(query, cursor_id)

    where(query, [m], m.inserted_at < ^cursor_message.inserted_at)
    |> or_where([m], m.inserted_at == ^cursor_message.inserted_at and m.id < ^cursor_message.id)
  end

  defp apply_after_cursor(query, cursor_id) do
    cursor_message = get_cursor_message(query, cursor_id)

    where(query, [m], m.inserted_at > ^cursor_message.inserted_at)
    |> or_where([m], m.inserted_at == ^cursor_message.inserted_at and m.id > ^cursor_message.id)
  end

  defp get_cursor_message(_query, cursor_id) do
    # This is a simplified implementation
    # In a real app, you'd need to determine the message type and fetch accordingly
    Repo.get(Message, cursor_id) || Repo.get(DirectMessage, cursor_id)
  end

  defp preload_reactions(query) do
    reactions_query = from r in Reaction, order_by: [asc: :id]
    preload(query, reactions: ^reactions_query)
  end

  defp get_message_by_type(:room, message_id), do: Chat.get_message!(message_id)

  defp get_message_by_type(:direct, message_id),
    do: Chat.DirectMessaging.get_direct_message!(message_id)

  defp authorized_to_search?(:room, room, user), do: Chat.joined?(room, user)

  defp authorized_to_search?(:direct, conversation, user),
    do: not is_nil(Chat.DirectMessaging.get_conversation_participant(conversation.id, user.id))

  defp authorized_to_search?(_type, _context, nil), do: false

  defp authorized_to_view_message?(:room, message, user), do: Chat.joined?(message.room, user)

  defp authorized_to_view_message?(:direct, message, user),
    do:
      not is_nil(
        Chat.DirectMessaging.get_conversation_participant(message.conversation_id, user.id)
      )

  defp authorized_to_update_message?(:room, message, user), do: message.user_id == user.id
  defp authorized_to_update_message?(:direct, message, user), do: message.user_id == user.id

  defp authorized_to_delete_message?(:room, message, user) do
    message.user_id == user.id ||
      Slap.Authorization.can_delete_any_room_message?(user, message.room)
  end

  defp authorized_to_delete_message?(:direct, message, user) do
    message.user_id == user.id ||
      Slap.Authorization.can_delete_any_conversation_message?(user, message.conversation)
  end

  defp authorized_to_react_to_message?(:room, message, user), do: Chat.joined?(message.room, user)

  defp authorized_to_react_to_message?(:direct, message, user),
    do:
      not is_nil(
        Chat.DirectMessaging.get_conversation_participant(message.conversation_id, user.id)
      )

  defp do_update_message(:room, message, attrs), do: Chat.update_message(message, attrs)

  defp do_update_message(:direct, message, attrs),
    do: Chat.DirectMessaging.update_direct_message(message, attrs, message.user)

  defp do_delete_message(:room, message), do: Chat.delete_message_by_id(message.id, message.user)

  defp do_delete_message(:direct, message),
    do: Chat.DirectMessaging.delete_direct_message(message, message.user)

  defp do_add_reaction(:room, message, emoji, user), do: Chat.add_reaction(emoji, message, user)
  defp do_add_reaction(:direct, message, emoji, user), do: Chat.add_reaction(emoji, message, user)

  defp do_remove_reaction(:room, message, emoji, user),
    do: Chat.remove_reaction(emoji, message, user)

  defp do_remove_reaction(:direct, message, emoji, user),
    do: Chat.remove_reaction(emoji, message, user)

  defp broadcast_reaction_update(type, action, reaction) do
    topic = get_broadcast_topic(type, get_context_id_from_reaction(type, reaction))

    Phoenix.PubSub.broadcast!(
      Slap.PubSub,
      topic,
      {get_broadcast_event(type, action), reaction}
    )
  end

  defp get_context_id(:room, message), do: message.room_id
  defp get_context_id(:direct, message), do: message.conversation_id

  defp get_context_id_from_reaction(:room, reaction), do: reaction.message.room_id
  defp get_context_id_from_reaction(:direct, reaction), do: reaction.message.conversation_id

  defp get_broadcast_topic(:room, room_id), do: Constants.pubsub_topic(:room, room_id)

  defp get_broadcast_topic(:direct, conversation_id),
    do: Constants.pubsub_topic(:conversation, conversation_id)

  defp get_broadcast_event(:room, :new), do: :new_message
  defp get_broadcast_event(:room, :updated), do: :updated_message
  defp get_broadcast_event(:room, :deleted), do: :message_deleted
  defp get_broadcast_event(:room, :added), do: :added_reaction
  defp get_broadcast_event(:room, :removed), do: :removed_reaction

  defp get_broadcast_event(:direct, :new), do: :new_direct_message
  defp get_broadcast_event(:direct, :updated), do: :updated_direct_message
  defp get_broadcast_event(:direct, :deleted), do: :direct_message_deleted
  defp get_broadcast_event(:direct, :added), do: :added_reaction
  defp get_broadcast_event(:direct, :removed), do: :removed_reaction

  defp sort_by_relevance(results, search_query) when is_binary(search_query) do
    # Simple relevance sorting - in a real app, you'd use PostgreSQL's ts_rank
    Enum.sort_by(
      results,
      fn message ->
        # Count occurrences of query terms in message body
        query_lower = String.downcase(search_query)
        body_lower = String.downcase(message.body)

        # Simple term frequency
        String.split(query_lower, " ")
        |> Enum.count(fn term -> String.contains?(body_lower, term) end)
      end,
      :desc
    )
  end

  defp sort_by_relevance(results, _query), do: results
end
