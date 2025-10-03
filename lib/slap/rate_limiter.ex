defmodule Slap.RateLimiter do
  @moduledoc """
  Unified rate limiting system for the Slap application.
  Provides configurable rate limiting for various operations.
  """

  alias Slap.Constants
  require Logger

  @type limit_key :: any()
  @type limit_result :: :ok | {:error, :rate_limited}
  @type limit_options :: [
          max_requests: non_neg_integer(),
          window_size: non_neg_integer(),
          key_prefix: String.t()
        ]

  # Default ETS table name
  @table_name :slap_rate_limits

  @doc """
  Checks if a request is allowed based on rate limits.

  ## Parameters
  - `key` - Unique identifier for the entity being rate limited (e.g., user_id, IP address)
  - `action` - The action being performed (e.g., :send_message, :login_attempt)
  - `opts` - Override options for this specific check

  ## Options
  - `:max_requests` - Maximum requests allowed in the window (default: varies by action)
  - `:window_size` - Time window in milliseconds (default: varies by action)
  - `:key_prefix` - Prefix for the key (default: action name)
  """
  @spec check_rate_limit(limit_key(), atom(), limit_options()) :: limit_result()
  def check_rate_limit(key, action, opts \\ []) do
    max_requests = Keyword.get(opts, :max_requests, get_max_requests(action))
    window_size = Keyword.get(opts, :window_size, get_window_size(action))
    key_prefix = Keyword.get(opts, :key_prefix, to_string(action))

    ensure_table_exists()

    composite_key = {key_prefix, key}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, composite_key) do
      [{^composite_key, count, window_start}] when now - window_start < window_size ->
        if count >= max_requests do
          log_rate_limit_violation(action, key, count, max_requests, window_size)
          {:error, :rate_limited}
        else
          :ets.update_element(@table_name, composite_key, {2, count + 1})
          :ok
        end

      _ ->
        # First request in window or window expired
        :ets.insert(@table_name, {composite_key, 1, now})
        :ok
    end
  end

  @doc """
  Resets the rate limit counter for a specific key and action.
  """
  @spec reset_rate_limit(limit_key(), atom()) :: :ok
  def reset_rate_limit(key, action) do
    ensure_table_exists()

    composite_key = {to_string(action), key}
    :ets.delete(@table_name, composite_key)

    :ok
  end

  @doc """
  Gets the current rate limit status for a key and action.
  Returns a map with count, remaining, and reset_time.
  """
  @spec get_rate_limit_status(limit_key(), atom()) :: %{
          count: non_neg_integer(),
          remaining: non_neg_integer(),
          reset_time: non_neg_integer() | nil,
          max_requests: non_neg_integer(),
          window_size: non_neg_integer()
        }
  def get_rate_limit_status(key, action) do
    ensure_table_exists()

    max_requests = get_max_requests(action)
    window_size = get_window_size(action)
    composite_key = {to_string(action), key}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, composite_key) do
      [{^composite_key, count, window_start}] when now - window_start < window_size ->
        remaining = max(0, max_requests - count)
        reset_time = window_start + window_size

        %{
          count: count,
          remaining: remaining,
          reset_time: reset_time,
          max_requests: max_requests,
          window_size: window_size
        }

      _ ->
        %{
          count: 0,
          remaining: max_requests,
          reset_time: nil,
          max_requests: max_requests,
          window_size: window_size
        }
    end
  end

  @doc """
  Checks if a user can send a message in a conversation.
  """
  @spec can_send_message?(non_neg_integer(), non_neg_integer()) :: boolean()
  def can_send_message?(user_id, conversation_id) do
    key = {user_id, conversation_id}
    check_rate_limit(key, :send_message) == :ok
  end

  @doc """
  Checks if a user can perform login attempts.
  """
  @spec can_attempt_login?(String.t()) :: boolean()
  def can_attempt_login?(identifier) do
    check_rate_limit(identifier, :login_attempt) == :ok
  end

  @doc """
  Checks if a user can create conversations.
  """
  @spec can_create_conversation?(non_neg_integer()) :: boolean()
  def can_create_conversation?(user_id) do
    check_rate_limit(user_id, :create_conversation) == :ok
  end

  @doc """
  Checks if a user can upload files.
  """
  @spec can_upload_file?(non_neg_integer()) :: boolean()
  def can_upload_file?(user_id) do
    check_rate_limit(user_id, :upload_file) == :ok
  end

  @doc """
  Checks if a user can perform search operations.
  """
  @spec can_search?(non_neg_integer()) :: boolean()
  def can_search?(user_id) do
    check_rate_limit(user_id, :search) == :ok
  end

  @doc """
  Cleans up expired rate limit entries.
  This should be called periodically to prevent memory leaks.
  """
  @spec cleanup_expired_entries() :: non_neg_integer()
  def cleanup_expired_entries() do
    ensure_table_exists()

    now = System.monotonic_time(:millisecond)

    # Get all entries and filter out expired ones
    all_entries = :ets.tab2list(@table_name)

    expired_entries =
      Enum.filter(all_entries, fn {_key, _count, window_start} ->
        # Cleanup entries older than 2x max window
        now - window_start > Constants.rate_limit_window() * 2
      end)

    # Delete expired entries
    Enum.each(expired_entries, fn {key, _count, _window_start} ->
      :ets.delete(@table_name, key)
    end)

    length(expired_entries)
  end

  @doc """
  Gets statistics about rate limiting.
  """
  @spec get_stats() :: %{
          total_entries: non_neg_integer(),
          active_entries: non_neg_integer(),
          memory_usage: non_neg_integer()
        }
  def get_stats() do
    ensure_table_exists()

    info = :ets.info(@table_name)
    now = System.monotonic_time(:millisecond)

    all_entries = :ets.tab2list(@table_name)

    active_entries =
      Enum.count(all_entries, fn {_key, _count, window_start} ->
        now - window_start < Constants.rate_limit_window()
      end)

    %{
      total_entries: Keyword.get(info, :size, 0),
      active_entries: active_entries,
      memory_usage: Keyword.get(info, :memory, 0)
    }
  end

  # Private functions

  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])

      _ ->
        :ok
    end
  end

  defp get_max_requests(action) do
    case action do
      :send_message -> Constants.rate_limit_max_messages()
      # 5 login attempts per window
      :login_attempt -> 5
      # 10 conversations per hour
      :create_conversation -> 10
      # 20 files per hour
      :upload_file -> 20
      # 100 searches per hour
      :search -> 100
      # Default to message rate limit
      _ -> Constants.rate_limit_max_messages()
    end
  end

  defp get_window_size(action) do
    case action do
      :send_message -> Constants.rate_limit_window()
      # 15 minutes
      :login_attempt -> 15 * 60 * 1000
      # 1 hour
      :create_conversation -> 60 * 60 * 1000
      # 1 hour
      :upload_file -> 60 * 60 * 1000
      # 1 hour
      :search -> 60 * 60 * 1000
      # Default to message rate limit window
      _ -> Constants.rate_limit_window()
    end
  end

  defp log_rate_limit_violation(action, key, count, max_requests, window_size) do
    Logger.warning(
      "Rate limit exceeded",
      action: action,
      key: key,
      count: count,
      max_requests: max_requests,
      window_size: window_size
    )
  end
end
