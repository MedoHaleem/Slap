defmodule Slap.Pagination do
  @moduledoc """
  Shared pagination utilities for the Slap application.
  Provides consistent pagination across all contexts.
  """

  alias Slap.Constants
  import Ecto.Query

  @type pagination_options :: [
    limit: non_neg_integer(),
    before: non_neg_integer() | nil,
    after: non_neg_integer() | nil,
    cursor_field: atom()
  ]

  @type pagination_result :: %{
    entries: [any()],
    metadata: %{
      has_next: boolean(),
      has_previous: boolean(),
      next_cursor: non_neg_integer() | nil,
      previous_cursor: non_neg_integer() | nil,
      total_count: non_neg_integer() | nil
    }
  }

  @doc """
  Applies cursor-based pagination to a query.

  ## Options
  - `:limit` - Maximum number of entries to return (default: Constants.default_page_size/0)
  - `:before` - Cursor to get entries before (older entries)
  - `:after` - Cursor to get entries after (newer entries)
  - `:cursor_field` - Field to use for cursor (default: :inserted_at)
  - `:order_by` - Order direction (default: :desc)
  """
  @spec paginate(Ecto.Query.t(), pagination_options()) :: pagination_result()
  def paginate(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, Constants.default_page_size())
    cursor_before = Keyword.get(opts, :before)
    cursor_after = Keyword.get(opts, :after)
    cursor_field = Keyword.get(opts, :cursor_field, :inserted_at)
    order_by = Keyword.get(opts, :order_by, :desc)

    # Apply cursor-based pagination
    query = apply_cursor_pagination(query, cursor_before, cursor_after, cursor_field, order_by)

    # Apply limit
    query = limit(query, ^limit)

    # Execute query
    entries = Slap.Repo.all(query)

    # Build metadata
    metadata = build_pagination_metadata(entries, limit, cursor_field, order_by)

    %{
      entries: entries,
      metadata: metadata
    }
  end

  @doc """
  Applies cursor-based pagination with total count.
  This includes an additional query to get the total count.
  """
  @spec paginate_with_count(Ecto.Query.t(), pagination_options()) :: pagination_result()
  def paginate_with_count(query, opts \\ []) do
    result = paginate(query, opts)

    # Get total count
    total_count = get_total_count(query)

    metadata = Map.put(result.metadata, :total_count, total_count)

    %{result | metadata: metadata}
  end

  @doc """
  Applies offset-based pagination (traditional page/limit).
  """
  @spec paginate_offset(Ecto.Query.t(), non_neg_integer(), non_neg_integer()) :: pagination_result()
  def paginate_offset(query, page, page_size \\ Constants.default_page_size()) do
    offset = (page - 1) * page_size

    # Get total count
    total_count = get_total_count(query)

    # Apply offset and limit
    entries =
      query
      |> offset(^offset)
      |> limit(^page_size)
      |> Slap.Repo.all()

    # Build metadata
    total_pages = ceil(total_count / page_size)
    has_next = page < total_pages
    has_previous = page > 1

    metadata = %{
      has_next: has_next,
      has_previous: has_previous,
      next_cursor: if(has_next, do: page + 1, else: nil),
      previous_cursor: if(has_previous, do: page - 1, else: nil),
      total_count: total_count,
      current_page: page,
      total_pages: total_pages,
      page_size: page_size
    }

    %{
      entries: entries,
      metadata: metadata
    }
  end

  @doc """
  Creates a cursor from a record.
  """
  @spec create_cursor(any(), atom()) :: any()
  def create_cursor(record, cursor_field \\ :inserted_at) do
    Map.get(record, cursor_field)
  end

  @doc """
  Checks if there are more entries available.
  """
  @spec has_more?(pagination_result()) :: boolean()
  def has_more?(%{metadata: %{has_next: has_next}}), do: has_next

  @doc """
  Gets the next cursor for pagination.
  """
  @spec next_cursor(pagination_result()) :: any() | nil
  def next_cursor(%{metadata: %{next_cursor: cursor}}), do: cursor

  @doc """
  Gets the previous cursor for pagination.
  """
  @spec previous_cursor(pagination_result()) :: any() | nil
  def previous_cursor(%{metadata: %{previous_cursor: cursor}}), do: cursor

  @doc """
  Validates pagination options.
  """
  @spec validate_options(pagination_options()) :: :ok | {:error, String.t()}
  def validate_options(opts) do
    limit = Keyword.get(opts, :limit, Constants.default_page_size())

    cond do
      limit > Constants.max_page_size() ->
        {:error, "Page size cannot exceed #{Constants.max_page_size()}"}

      limit < 1 ->
        {:error, "Page size must be at least 1"}

      not is_nil(Keyword.get(opts, :before)) and not is_nil(Keyword.get(opts, :after)) ->
        {:error, "Cannot specify both before and after cursors"}

      true ->
        :ok
    end
  end

  # Private functions

  defp apply_cursor_pagination(query, nil, nil, _cursor_field, _order_by) do
    # No cursor, return query as is
    query
  end

  defp apply_cursor_pagination(query, cursor_before, nil, cursor_field, order_by) do
    # Get entries before cursor (older entries)
    cursor_value = get_cursor_value(query, cursor_before)

    if order_by == :desc do
      where(query, [q], field(q, ^cursor_field) < ^cursor_value)
    else
      where(query, [q], field(q, ^cursor_field) < ^cursor_value)
    end
  end

  defp apply_cursor_pagination(query, nil, cursor_after, cursor_field, order_by) do
    # Get entries after cursor (newer entries)
    cursor_value = get_cursor_value(query, cursor_after)

    if order_by == :desc do
      where(query, [q], field(q, ^cursor_field) > ^cursor_value)
    else
      where(query, [q], field(q, ^cursor_field) > ^cursor_value)
    end
  end

  defp get_cursor_value(query, cursor_id) do
    # Get the actual cursor value from the database
    # This assumes cursor_id is the primary key
    # For timestamp cursors, you might need a different approach

    # For now, we'll assume cursor_id is the actual value we need
    # In a real implementation, you might need to fetch the record first
    cursor_id
  end

  defp build_pagination_metadata(entries, limit, cursor_field, order_by) do
    has_next = length(entries) > limit
    has_previous = false # Would need additional query to determine

    # Remove the extra entry if we fetched one more to check for next page
    entries = if has_next, do: Enum.take(entries, limit), else: entries

    # Get cursors from first and last entries
    next_cursor = if has_next and entries != [] do
      last_entry = List.last(entries)
      create_cursor(last_entry, cursor_field)
    else
      nil
    end

    previous_cursor = if entries != [] do
      first_entry = List.first(entries)
      create_cursor(first_entry, cursor_field)
    else
      nil
    end

    %{
      has_next: has_next,
      has_previous: has_previous,
      next_cursor: next_cursor,
      previous_cursor: previous_cursor,
      total_count: nil
    }
  end

  defp get_total_count(query) do
    # Remove order_by and limit to get accurate count
    count_query =
      query
      |> exclude(:order_by)
      |> exclude(:limit)
      |> exclude(:offset)

    Slap.Repo.aggregate(count_query, :count, :id)
  end
end
