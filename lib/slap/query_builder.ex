defmodule Slap.QueryBuilder do
  @moduledoc """
  Shared query builder utilities for the Slap application.
  Provides common query patterns and builders for Ecto queries.
  """

  import Ecto.Query

  @doc """
  Builds a query for messages with optional filters.
  """
  @spec messages_query(keyword()) :: Ecto.Query.t()
  def messages_query(opts \\ []) do
    schema = opts[:schema] || Slap.Chat.Message
    from(m in schema)
    |> maybe_filter_by_room(opts[:room_id])
    |> maybe_filter_by_conversation(opts[:conversation_id])
    |> maybe_filter_by_user(opts[:user_id])
    |> maybe_filter_by_date_range(opts[:start_date], opts[:end_date])
    |> maybe_include_reactions(opts[:include_reactions])
    |> maybe_include_attachments(opts[:include_attachments])
    |> maybe_include_replies(opts[:include_replies])
    |> maybe_include_user(opts[:include_user] || true)
    |> maybe_order_by(opts[:order_by] || [desc: :inserted_at])
  end

  @doc """
  Builds a query for unread messages.
  """
  @spec unread_messages_query(any(), any(), keyword()) :: Ecto.Query.t()
  def unread_messages_query(user, context, opts \\ []) do
    case context do
      %Slap.Chat.Room{} = room ->
        from(m in Slap.Chat.Message,
          where: m.room_id == ^room.id,
          where: m.inserted_at > ^(opts[:last_read_at] || DateTime.utc_now()),
          where: m.user_id != ^user.id
        )

      %Slap.Chat.Conversation{} = conversation ->
        from(m in Slap.Chat.DirectMessage,
          where: m.conversation_id == ^conversation.id,
          where: m.inserted_at > ^(opts[:last_read_at] || DateTime.utc_now()),
          where: m.user_id != ^user.id
        )
    end
  end

  @doc """
  Builds a query for search with full-text search capabilities.
  """
  @spec search_query(Ecto.Query.t(), String.t(), keyword()) :: Ecto.Query.t()
  def search_query(base_query, search_term, opts \\ []) do
    search_term = String.trim(search_term)

    if search_term == "" do
      base_query
    else
      # Check if search term contains special characters that might break full-text search
      if String.match?(search_term, ~r/[&@#$%]/) do
        # Fall back to simple LIKE search for special characters
        apply_like_search(base_query, search_term, opts)
      else
        # Use full-text search for regular text
        apply_fulltext_search(base_query, search_term, opts)
      end
    end
  end

  @doc """
  Builds a query for counting unread items.
  """
  @spec unread_count_query(any(), any(), keyword()) :: Ecto.Query.t()
  def unread_count_query(user, context, opts \\ []) do
    case context do
      %Slap.Chat.Room{} = room ->
        from(m in Slap.Chat.Message,
          where: m.room_id == ^room.id,
          where: m.inserted_at > ^(opts[:last_read_at] || DateTime.utc_now()),
          where: m.user_id != ^user.id,
          select: count(m.id)
        )

      %Slap.Chat.Conversation{} = conversation ->
        from(m in Slap.Chat.DirectMessage,
          where: m.conversation_id == ^conversation.id,
          where: m.inserted_at > ^(opts[:last_read_at] || DateTime.utc_now()),
          where: m.user_id != ^user.id,
          select: count(m.id)
        )
    end
  end

  @doc """
  Builds a query for presence information.
  """
  @spec presence_query(keyword()) :: Ecto.Query.t()
  def presence_query(opts \\ []) do
    from(p in SlapWeb.Presence)
    |> maybe_filter_by_user(opts[:user_id])
    |> maybe_filter_by_topic(opts[:topic])
    |> maybe_filter_by_online_status(opts[:online_only])
  end

  @doc """
  Builds a query for user statistics.
  """
  @spec user_stats_query(non_neg_integer(), keyword()) :: Ecto.Query.t()
  def user_stats_query(user_id, opts \\ []) do
    message_count_query =
      from(m in Slap.Chat.Message,
        where: m.user_id == ^user_id,
        select: count(m.id)
      )

    direct_message_count_query =
      from(m in Slap.Chat.DirectMessage,
        where: m.user_id == ^user_id,
        select: count(m.id)
      )

    reaction_count_query =
      from(r in Slap.Chat.Reaction,
        where: r.user_id == ^user_id,
        select: count(r.id)
      )

    %{
      message_count: Slap.Repo.one(message_count_query),
      direct_message_count: Slap.Repo.one(direct_message_count_query),
      reaction_count: Slap.Repo.one(reaction_count_query)
    }
  end

  @doc """
  Builds a query for activity logs.
  """
  @spec activity_query(keyword()) :: Ecto.Query.t()
  def activity_query(opts \\ []) do
    # This would be used with an activity log schema if implemented
    # For now, it's a placeholder for future functionality
    from(a in "activities")
    |> maybe_filter_by_user(opts[:user_id])
    |> maybe_filter_by_action(opts[:action])
    |> maybe_filter_by_date_range(opts[:start_date], opts[:end_date])
    |> maybe_order_by(opts[:order_by] || [desc: :inserted_at])
  end

  @doc """
  Applies pagination to a query.
  """
  @spec paginate_query(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  def paginate_query(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  @doc """
  Applies cursor-based pagination to a query.
  """
  @spec cursor_paginate_query(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  def cursor_paginate_query(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    cursor_before = Keyword.get(opts, :before)
    cursor_after = Keyword.get(opts, :after)
    cursor_field = Keyword.get(opts, :cursor_field, :inserted_at)

    query =
      cond do
        cursor_before ->
          apply_before_cursor(query, cursor_before, cursor_field)

        cursor_after ->
          apply_after_cursor(query, cursor_after, cursor_field)

        true ->
          query
      end

    limit(query, ^limit)
  end

  @doc """
  Preloads associations for a query.
  """
  @spec with_preloads(Ecto.Query.t(), [atom()], keyword()) :: Ecto.Query.t()
  def with_preloads(query, preloads, opts \\ []) do
    preload_options = Keyword.get(opts, :preload_options, [])

    case preload_options do
      [] -> preload(query, ^preloads)
      _ -> preload(query, ^preloads, ^preload_options)
    end
  end

  # Private helper functions

  defp maybe_filter_by_room(query, nil), do: query
  defp maybe_filter_by_room(query, room_id), do: where(query, [m], m.room_id == ^room_id)

  defp maybe_filter_by_conversation(query, nil), do: query
  defp maybe_filter_by_conversation(query, conversation_id), do: where(query, [m], m.conversation_id == ^conversation_id)

  defp maybe_filter_by_user(query, nil), do: query
  defp maybe_filter_by_user(query, user_id), do: where(query, [m], m.user_id == ^user_id)

  defp maybe_filter_by_date_range(query, nil, nil), do: query
  defp maybe_filter_by_date_range(query, start_date, nil), do: where(query, [m], m.inserted_at >= ^start_date)
  defp maybe_filter_by_date_range(query, nil, end_date), do: where(query, [m], m.inserted_at <= ^end_date)
  defp maybe_filter_by_date_range(query, start_date, end_date), do: where(query, [m], m.inserted_at >= ^start_date and m.inserted_at <= ^end_date)

  defp maybe_include_reactions(query, true), do: preload(query, reactions: ^from(r in Slap.Chat.Reaction, order_by: [asc: r.id]))
  defp maybe_include_reactions(query, _), do: query

  defp maybe_include_attachments(query, true), do: preload(query, :attachments)
  defp maybe_include_attachments(query, _), do: query

  defp maybe_include_replies(query, true), do: preload(query, replies: ^from(r in Slap.Chat.Reply, order_by: [asc: r.id]))
  defp maybe_include_replies(query, _), do: query

  defp maybe_include_user(query, true), do: preload(query, :user)
  defp maybe_include_user(query, _), do: query

  defp maybe_order_by(query, order_by), do: order_by(query, ^order_by)

  defp maybe_filter_by_user(query, nil), do: query
  defp maybe_filter_by_user(query, user_id), do: where(query, [p], p.user_id == ^user_id)

  defp maybe_filter_by_topic(query, nil), do: query
  defp maybe_filter_by_topic(query, topic), do: where(query, [p], p.topic == ^topic)

  defp maybe_filter_by_online_status(query, nil), do: query
  defp maybe_filter_by_online_status(query, true), do: where(query, [p], not is_nil(p.metadatas))

  defp maybe_filter_by_action(query, nil), do: query
  defp maybe_filter_by_action(query, action), do: where(query, [a], a.action == ^action)

  defp apply_like_search(query, search_term, opts) do
    search_field = Keyword.get(opts, :search_field, :body)

    where(query, [m], like(field(m, ^search_field), ^"%#{search_term}%"))
  end

  defp apply_fulltext_search(query, search_term, opts) do
    # For now, use a simple LIKE search instead of full-text search
    # to avoid PostgreSQL type issues
    search_field = Keyword.get(opts, :search_field, :body)

    where(
      query,
      [m],
      like(field(m, ^search_field), ^"%#{search_term}%")
    )
  end

  defp apply_before_cursor(query, cursor_id, cursor_field) do
    # Get the cursor value from the database
    cursor_value = get_cursor_value(query, cursor_id, cursor_field)

    where(query, [m], field(m, ^cursor_field) < ^cursor_value)
    |> or_where([m], field(m, ^cursor_field) == ^cursor_value and m.id < ^cursor_id)
  end

  defp apply_after_cursor(query, cursor_id, cursor_field) do
    # Get the cursor value from the database
    cursor_value = get_cursor_value(query, cursor_id, cursor_field)

    where(query, [m], field(m, ^cursor_field) > ^cursor_value)
    |> or_where([m], field(m, ^cursor_field) == ^cursor_value and m.id > ^cursor_id)
  end

  defp get_cursor_value(query, cursor_id, cursor_field) do
    # This is a simplified implementation
    # In a real app, you'd need to determine the schema and fetch accordingly
    case query.from.source do
      {_source, %Slap.Chat.Message{}} ->
        message = Slap.Repo.get(Slap.Chat.Message, cursor_id)
        Map.get(message, cursor_field)

      {_source, %Slap.Chat.DirectMessage{}} ->
        message = Slap.Repo.get(Slap.Chat.DirectMessage, cursor_id)
        Map.get(message, cursor_field)

      _ ->
        nil
    end
  end
end
