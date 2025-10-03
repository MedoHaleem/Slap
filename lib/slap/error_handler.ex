defmodule Slap.ErrorHandler do
  @moduledoc """
  Comprehensive error handling system for the Slap application.
  Provides standardized error types, transformations, and responses.
  """

  alias Slap.Constants

  @type error_type :: :validation | :authorization | :not_found | :rate_limit | :server | :network
  @type error_context :: map()
  @type error_result :: {:error, error_type(), String.t(), error_context()}

  @doc """
  Transforms various error types into a standardized format.
  """
  @spec normalize_error(any()) :: error_result()
  def normalize_error(error) do
    case error do
      %Ecto.Changeset{} = changeset ->
        normalize_changeset_error(changeset)

      {:error, %Ecto.Changeset{} = changeset} ->
        normalize_changeset_error(changeset)

      {:error, :authorization, message, context} ->
        {:error, :authorization, message, context}

      {:error, :not_found, message, context} ->
        {:error, :not_found, message, context}

      {:error, :rate_limit, message, context} ->
        {:error, :rate_limit, message, context}

      {:error, :network, message, context} ->
        {:error, :network, message, context}

      {:error, reason} when is_binary(reason) ->
        {:error, :server, reason, %{}}

      {:error, reason} when is_atom(reason) ->
        {:error, :server, Atom.to_string(reason), %{}}

      %Phoenix.ActionClauseError{} ->
        {:error, :server, "Invalid request parameters", %{}}

      %Plug.Conn.WrapperError{} ->
        {:error, :server, "Internal server error", %{}}

      %RuntimeError{message: message} ->
        {:error, :server, message, %{}}

      _ ->
        {:error, :server, "An unexpected error occurred", %{}}
    end
  end

  @doc """
  Transforms Ecto changeset errors into a standardized format.
  """
  @spec normalize_changeset_error(Ecto.Changeset.t()) :: error_result()
  def normalize_changeset_error(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    # Get the first error for simplicity, or join all errors
    error_message =
      errors
      |> Enum.map(fn {field, messages} ->
        "#{field}: #{Enum.join(messages, ", ")}"
      end)
      |> Enum.join("; ")

    {:error, :validation, error_message, %{errors: errors}}
  end

  @doc """
  Creates a standardized authorization error.
  """
  @spec authorization_error(String.t()) :: error_result()
  def authorization_error(message \\ "Not authorized") do
    {:error, :authorization, message, %{}}
  end

  @doc """
  Creates a standardized not found error.
  """
  @spec not_found_error(String.t()) :: error_result()
  def not_found_error(resource \\ "Resource") do
    {:error, :not_found, "#{resource} not found", %{}}
  end

  @doc """
  Creates a standardized rate limit error.
  """
  @spec rate_limit_error() :: error_result()
  def rate_limit_error do
    {:error, :rate_limit, Constants.get_error_message(:rate_limit_exceeded), %{}}
  end

  @doc """
  Creates a standardized validation error.
  """
  @spec validation_error(String.t()) :: error_result()
  def validation_error(message) do
    {:error, :validation, message, %{}}
  end

  @doc """
  Creates a standardized server error.
  """
  @spec server_error(String.t()) :: error_result()
  def server_error(message \\ "Internal server error") do
    {:error, :server, message, %{}}
  end

  @doc """
  Creates a standardized network error.
  """
  @spec network_error(String.t()) :: error_result()
  def network_error(message \\ "Network error") do
    {:error, :network, message, %{}}
  end

  @doc """
  Creates a standardized error with a custom message.
  """
  @spec error_with_message(String.t()) :: error_result()
  def error_with_message(message) do
    {:error, :server, message, %{}}
  end

  @doc """
  Formats an error for API responses.
  """
  @spec format_api_error(error_result()) :: map()
  def format_api_error({:error, type, message, context}) do
    %{
      error: true,
      type: type,
      message: message,
      context: context,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Formats an error for LiveView flash messages.
  """
  @spec format_flash_error(error_result()) :: {atom(), String.t()}
  def format_flash_error({:error, type, message, _context}) do
    flash_type =
      case type do
        :validation -> :error
        :authorization -> :error
        :not_found -> :error
        :rate_limit -> :error
        :server -> :error
        :network -> :error
      end

    {flash_type, message}
  end

  @doc """
  Formats an error for logging.
  """
  @spec format_log_error(error_result(), keyword()) :: String.t()
  def format_log_error({:error, type, message, context}, opts \\ []) do
    context_str =
      if map_size(context) > 0 do
        " Context: #{inspect(context)}"
      else
        ""
      end

    user_id = Keyword.get(opts, :user_id)

    user_str =
      if user_id do
        " User: #{user_id}"
      else
        ""
      end

    "[#{String.upcase(Atom.to_string(type))}] #{message}#{context_str}#{user_str}"
  end

  @doc """
  Handles an error with appropriate actions based on type.
  """
  @spec handle_error(any(), keyword()) :: error_result()
  def handle_error(error, opts \\ []) do
    normalized = normalize_error(error)

    # Log the error
    log_error(normalized, opts)

    # Take additional actions based on error type
    case normalized do
      {:error, :server, _, _} ->
        # Report server errors to monitoring service
        report_server_error(normalized, opts)

      {:error, :rate_limit, _, _} ->
        # Log rate limit violations for monitoring
        log_rate_limit_violation(normalized, opts)

      _ ->
        # No special handling for other error types
        :ok
    end

    normalized
  end

  @doc """
  Wraps a function with error handling.
  """
  @spec with_error_handling((-> any()), keyword()) :: {:ok, any()} | error_result()
  def with_error_handling(fun, opts \\ []) do
    try do
      case fun.() do
        {:ok, result} -> {:ok, result}
        {:error, _} = error -> handle_error(error, opts)
        result -> {:ok, result}
      end
    rescue
      error -> handle_error(error, opts)
    catch
      :throw, value -> handle_error(value, opts)
      :exit, reason -> handle_error({:exit, reason}, opts)
    end
  end

  @doc """
  Creates a user-friendly error message from a technical error.
  """
  @spec user_friendly_message(error_result()) :: String.t()
  def user_friendly_message({:error, type, message, _context}) do
    case type do
      :validation -> message
      :authorization -> "You don't have permission to perform this action"
      :not_found -> "The requested resource was not found"
      :rate_limit -> Constants.get_error_message(:rate_limit_exceeded)
      :server -> "Something went wrong. Please try again later"
      :network -> "Connection error. Please check your internet connection"
    end
  end

  @doc """
  Checks if an error is recoverable (can be retried).
  """
  @spec recoverable?(error_result()) :: boolean()
  def recoverable?({:error, type, _message, _context}) do
    case type do
      :network -> true
      # Some server errors might be recoverable
      :server -> true
      # Can retry after waiting
      :rate_limit -> true
      _ -> false
    end
  end

  @doc """
  Gets the suggested retry delay for recoverable errors.
  """
  @spec retry_delay(error_result()) :: non_neg_integer()
  def retry_delay({:error, type, _message, _context}) do
    case type do
      # 5 seconds
      :rate_limit -> 5_000
      # 1 second
      :network -> 1_000
      # 10 seconds
      :server -> 10_000
      _ -> 0
    end
  end

  # Private functions

  defp log_error(error, opts) do
    require Logger

    log_level =
      case error do
        {:error, :validation, _, _} -> :warning
        {:error, :authorization, _, _} -> :warning
        {:error, :not_found, _, _} -> :info
        {:error, :rate_limit, _, _} -> :warning
        {:error, :server, _, _} -> :error
        {:error, :network, _, _} -> :error
      end

    Logger.log(log_level, format_log_error(error, opts))
  end

  defp report_server_error(error, opts) do
    # In a real application, you would report to a monitoring service
    # like Sentry, Bugsnag, etc.
    require Logger

    Logger.error("Server error reported: #{format_log_error(error, opts)}")
  end

  defp log_rate_limit_violation(error, opts) do
    require Logger

    Logger.warning("Rate limit violation: #{format_log_error(error, opts)}")
  end
end
