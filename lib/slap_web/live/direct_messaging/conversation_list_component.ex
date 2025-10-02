defmodule SlapWeb.DirectMessaging.ConversationListComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers
  alias Slap.Constants

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dm-messages-container flex-1 overflow-y-auto">
      <%= for conversation <- @conversations do %>
        <button
          phx-click="select_conversation"
          phx-value-id={conversation.id}
          phx-target={@myself}
          class={"w-full p-4 text-left hover:bg-gray-50 border-b border-gray-100 #{if @selected_conversation && @selected_conversation.id == conversation.id, do: "bg-blue-50 border-l-4 border-l-blue-500", else: ""}"}
        >
          <div class="flex items-center justify-between">
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-gray-900 truncate">
                {conversation_title(conversation, @current_user)}
              </p>

              <p class="text-xs text-gray-500 truncate">
                <%= if conversation.last_message_at do %>
                  {format_conversation_timestamp(conversation.last_message_at)}
                <% else %>
                  No messages yet
                <% end %>
              </p>
            </div>

            <.unread_badge count={get_unread_count(conversation, @current_user)} />
          </div>
        </button>
      <% end %>
    </div>

    <%= if Enum.empty?(@conversations) do %>
      <.empty_state
        title="No conversations yet"
        description="Start a new conversation by clicking the DM icon next to a user's name"
        icon="hero-chat-bubble-bottom-center-text"
      >
        <:actions>
          <button
            phx-click="create_group_conversation"
            phx-target={@myself}
            class={Constants.get_css_class(:primary_button)}
          >
            Create Group Conversation
          </button>
        </:actions>
      </.empty_state>
    <% end %>
    """
  end

  @impl true
  def handle_event("select_conversation", %{"id" => conversation_id}, socket) do
    send(self(), {:select_conversation, conversation_id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_group_conversation", _params, socket) do
    send(self(), {:create_group_conversation})
    {:noreply, socket}
  end

  # Helper functions
  defp conversation_title(conversation, current_user) do
    # Extract other participants
    other_participants =
      Enum.reject(conversation.conversation_participants, &(&1.user_id == current_user.id))
      |> Enum.map(fn participant -> participant.user.username end)
      |> Enum.join(", ")

    if other_participants == "" do
      conversation.title || "Direct Messages"
    else
      "Conversation with #{other_participants}"
    end
  end

  defp get_unread_count(conversation, _current_user) do
    # Use the pre-calculated unread count from the optimized query
    Map.get(conversation, :unread_count, 0)
  end

  defp format_conversation_timestamp(timestamp) do
    if function_exported?(Timex, :format, 2) do
      Timex.format!(timestamp, "{relative}")
    else
      Calendar.strftime(timestamp, Constants.message_timestamp_format())
    end
  end
end
