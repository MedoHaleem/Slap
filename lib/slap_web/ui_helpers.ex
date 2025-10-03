defmodule SlapWeb.UIHelpers do
  @moduledoc """
  Shared UI helper functions for the Slap application.
  Provides common UI patterns and CSS classes.
  """

  use Phoenix.Component

  alias Slap.Constants

  @doc """
  Renders a primary button with consistent styling.
  """
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false
  attr :rest, :global

  slot :inner_block, required: true

  def primary_button(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <button
      class={["#{Constants.get_css_class(:primary_button)}", @class]}
      disabled={@disabled}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a secondary button with consistent styling.
  """
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  def secondary_button(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <button class={["#{Constants.get_css_class(:secondary_button)}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a danger button with consistent styling.
  """
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  def danger_button(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <button class={["#{Constants.get_css_class(:danger_button)}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a success button with consistent styling.
  """
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  def success_button(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <button class={["#{Constants.get_css_class(:success_button)}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a form input with consistent styling.
  """
  attr :type, :string, default: "text"
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :class, :string, default: ""
  attr :rest, :global

  def form_input(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      class={["#{Constants.get_css_class(:input_field)}", @class]}
      {@rest}
    />
    """
  end

  @doc """
  Renders a user avatar with consistent styling.
  """
  attr :user, :map, required: true
  # "small", "normal", "large"
  attr :size, :string, default: "normal"
  attr :class, :string, default: ""
  attr :rest, :global

  def user_avatar(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    avatar_class =
      case assigns.size do
        "small" -> Constants.get_css_class(:small_avatar)
        "large" -> Constants.get_css_class(:large_avatar)
        _ -> Constants.get_css_class(:avatar)
      end

    assigns = assign(assigns, :avatar_class, avatar_class)

    ~H"""
    <img
      src={@user.avatar_path || "/images/profile_avatar.png"}
      class={[@avatar_class, @class]}
      alt={@user.username}
      {@rest}
    />
    """
  end

  @doc """
  Renders an unread badge with consistent styling.
  """
  attr :count, :integer, required: true
  attr :class, :string, default: ""
  attr :rest, :global

  def unread_badge(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <%= if @count > 0 do %>
      <span class={["#{Constants.get_css_class(:unread_badge)}", @class]} {@rest}>
        {@count}
      </span>
    <% end %>
    """
  end

  @doc """
  Renders an online/offline indicator.
  """
  attr :online, :boolean, required: true
  attr :class, :string, default: ""
  attr :rest, :global

  def presence_indicator(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    indicator_class =
      if assigns.online do
        Constants.get_css_class(:online_indicator)
      else
        Constants.get_css_class(:offline_indicator)
      end

    assigns = assign(assigns, :indicator_class, indicator_class)

    ~H"""
    <div class={[@indicator_class, @class]} {@rest}></div>
    """
  end

  @doc """
  Renders a role badge with consistent styling.
  """
  attr :role, :string, required: true
  attr :class, :string, default: ""
  attr :rest, :global

  def role_badge(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    badge_class = Constants.get_role_badge_class(assigns.role)

    assigns = assign(assigns, :badge_class, badge_class)

    ~H"""
    <span class={[@badge_class, @class]} {@rest}>
      {String.capitalize(@role)}
    </span>
    """
  end

  @doc """
  Renders a message container with consistent styling.
  """
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  def message_container(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <div class={["#{Constants.get_css_class(:message_container)}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders message content with consistent styling.
  """
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  def message_content(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <div class={["#{Constants.get_css_class(:message_content)}", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a message timestamp with consistent styling.
  """
  attr :timestamp, :any, required: true
  attr :format, :string, default: "relative"
  attr :class, :string, default: ""
  attr :rest, :global

  def message_timestamp(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    formatted_time =
      case assigns.format do
        "relative" ->
          if function_exported?(Timex, :format, 2) do
            Timex.format!(assigns.timestamp, "{relative}")
          else
            Calendar.strftime(assigns.timestamp, Constants.message_timestamp_format())
          end

        "absolute" ->
          Calendar.strftime(assigns.timestamp, Constants.message_timestamp_format())

        "datetime" ->
          Calendar.strftime(assigns.timestamp, Constants.datetime_format())

        _ ->
          Calendar.strftime(assigns.timestamp, Constants.message_timestamp_format())
      end

    assigns = assign(assigns, :formatted_time, formatted_time)

    ~H"""
    <span class={["#{Constants.get_css_class(:message_timestamp)}", @class]} {@rest}>
      {@formatted_time}
    </span>
    """
  end

  @doc """
  Renders message body with consistent styling.
  """
  attr :body, :string, required: true
  attr :class, :string, default: ""
  attr :rest, :global

  def message_body(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <p class={["#{Constants.get_css_class(:message_body)}", @class]} {@rest}>
      {@body}
    </p>
    """
  end

  @doc """
  Highlights search terms in text.
  """
  attr :text, :string, required: true
  attr :query, :string, required: true
  attr :class, :string, default: ""

  def highlighted_text(assigns) do
    assigns = assign_new(assigns, :class, fn -> Constants.get_css_class(:search_highlight) end)

    highlighted = highlight_search_terms(assigns.text, assigns.query, assigns.class)

    assigns = assign(assigns, :highlighted, highlighted)

    ~H"""
    <span>{@highlighted}</span>
    """
  end

  @doc """
  Renders a loading spinner.
  """
  # "small", "medium", "large"
  attr :size, :string, default: "medium"
  attr :class, :string, default: ""
  attr :rest, :global

  def loading_spinner(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    size_class =
      case assigns.size do
        "small" -> "w-4 h-4"
        "large" -> "w-8 h-8"
        _ -> "w-6 h-6"
      end

    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div
      class={[
        "animate-spin rounded-full border-2 border-gray-300 border-t-blue-600",
        @size_class,
        @class
      ]}
      {@rest}
    >
    </div>
    """
  end

  @doc """
  Renders an empty state with consistent styling.
  """
  attr :title, :string, required: true
  attr :description, :string, default: ""
  attr :icon, :string, default: "hero-document"
  attr :class, :string, default: ""
  attr :rest, :global

  slot :actions

  def empty_state(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <div class={["flex flex-col items-center justify-center py-12", @class]} {@rest}>
      <div class="w-12 h-12 text-gray-400 mb-4">
        <svg class="w-12 h-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
          />
        </svg>
      </div>

      <h3 class="text-lg font-medium text-gray-900 mb-2">{@title}</h3>

      <%= if @description != "" do %>
        <p class="text-gray-500 text-center mb-4">{@description}</p>
      <% end %>

      <%= if @actions != [] do %>
        <div class="flex space-x-3">
          {render_slot(@actions)}
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Formats a timestamp for display.
  """
  def format_timestamp(timestamp, format \\ "relative") do
    case format do
      "relative" ->
        if function_exported?(Timex, :format, 2) do
          Timex.format!(timestamp, "{relative}")
        else
          Calendar.strftime(timestamp, Constants.message_timestamp_format())
        end

      "absolute" ->
        Calendar.strftime(timestamp, Constants.message_timestamp_format())

      "datetime" ->
        Calendar.strftime(timestamp, Constants.datetime_format())

      "date" ->
        Calendar.strftime(timestamp, Constants.date_format())

      _ ->
        Calendar.strftime(timestamp, Constants.message_timestamp_format())
    end
  end

  @doc """
  Truncates text to a specified length.
  """
  def truncate_text(text, max_length \\ 50) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  # Private functions

  defp highlight_search_terms(text, query, highlight_class) do
    if query && query != "" do
      # Escape special regex characters in the query
      escaped_query = Regex.escape(query)

      # Create regex with word boundaries to match whole words only
      regex = ~r/#{escaped_query}/i

      # Replace matches with highlighted span
      String.replace(text, regex, fn match ->
        "<span class=\"#{highlight_class}\">#{match}</span>"
      end)
    else
      text
    end
  end
end
