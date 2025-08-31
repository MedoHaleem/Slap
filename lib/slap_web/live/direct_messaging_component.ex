defmodule SlapWeb.DirectMessagingComponent do
  use SlapWeb, :live_component

  alias Slap.DirectMessaging

  @impl true
  def update(assigns, socket) do
    # Assign all passed assigns first, excluding reserved assigns
    assigns = Map.drop(assigns, [:myself])
    socket = assign(socket, assigns)

    # Initialize conversations only if not already present and connected
    socket =
      if socket.assigns[:conversations] == nil && Phoenix.LiveView.connected?(socket) do
        conversations = DirectMessaging.get_user_conversations(socket.assigns.current_user)
        unread_count = DirectMessaging.get_unread_conversation_count(socket.assigns.current_user)

        socket
        |> assign(conversations: conversations, unread_count: unread_count)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => conversation_id}, socket) do
    current_user = socket.assigns.current_user

    case DirectMessaging.get_conversation_with_unread_count(current_user, conversation_id) do
      {conversation, _unread_count} ->
        DirectMessaging.subscribe_to_conversation(conversation)
        DirectMessaging.mark_conversation_read(conversation, current_user)

        messages = DirectMessaging.list_direct_messages(conversation.id)

        socket =
          socket
          |> assign(
            selected_conversation: conversation,
            messages: messages,
            unread_count: DirectMessaging.get_unread_conversation_count(current_user)
          )

        {:noreply, socket}

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    case DirectMessaging.send_direct_message(conversation, %{body: body}, current_user) do
      {:ok, message} ->
        socket =
          socket
          |> assign(message_form: to_form(%{"body" => ""}))
          |> assign(messages: [message | socket.assigns.messages])

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  @impl true
  def handle_event("close_dm", _params, socket) do
    send(self(), :close_dm_panel)
    {:noreply, socket}
  end

  def handle_info({:new_direct_message, message}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    if conversation && conversation.id == message.conversation_id do
      # Only add the message if it wasn't sent by the current user
      # Messages from current user are already added optimistically when sending
      if message.user_id != current_user.id do
        messages = [message | socket.assigns.messages]

        socket =
          socket
          |> assign(messages: messages)
          |> then(fn s ->
            # Mark conversation as read but don't use the return value
            DirectMessaging.mark_conversation_read(conversation, current_user)
            s
          end)

        {:noreply, socket}
      else
        # For messages sent by current user, just mark as read
        DirectMessaging.mark_conversation_read(conversation, current_user)
        {:noreply, socket}
      end
    else
      # Update unread count if message is for a different conversation
      unread_count = DirectMessaging.get_unread_conversation_count(current_user)
      {:noreply, assign(socket, unread_count: unread_count)}
    end
  end

  def handle_info({:direct_message_deleted, message}, socket) do
    conversation = socket.assigns.selected_conversation

    if conversation && conversation.id == message.conversation_id do
      messages = Enum.reject(socket.assigns.messages, &(&1.id == message.id))
      {:noreply, assign(socket, messages: messages)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:conversation_read, user_id, _timestamp}, socket) do
    current_user = socket.assigns.current_user

    if user_id != current_user.id do
      # Update unread count when other participants read messages
      unread_count = DirectMessaging.get_unread_conversation_count(current_user)
      {:noreply, assign(socket, unread_count: unread_count)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 overflow-hidden">
      <!-- Overlay background -->
      <div
        class="dm-backdrop absolute inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
        phx-click="close_dm"
        phx-target={@myself}
      >
      </div>

    <!-- Slide-over panel -->
      <div class="absolute inset-y-0 right-0 max-w-full flex">
        <div class="w-screen max-w-md">
          <div class="dm-panel h-full flex flex-col bg-white shadow-xl">
            <!-- Header -->
            <div class="flex items-center justify-between px-4 py-5 sm:px-6 border-b border-gray-200">
              <h2 class="text-lg font-medium text-gray-900">Direct Messages</h2>
              <button
                type="button"
                class="rounded-md text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                phx-click="close_dm"
                phx-target={@myself}
              >
                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>

            <div class="flex-1 flex flex-col overflow-hidden">
              <%= if @selected_conversation do %>
                <!-- Conversation header -->
                <div class="border-b border-gray-200 bg-white px-4 py-3">
                  <h3 class="text-md font-semibold text-gray-900">
                    {conversation_title(@selected_conversation, @current_user)}
                  </h3>
                  <p class="text-xs text-gray-600">
                    {length(@selected_conversation.conversation_participants)} participants
                  </p>
                </div>

    <!-- Messages list -->
                <div
                  class="dm-messages-container flex-1 overflow-y-auto p-4 space-y-4"
                  id="messages-container"
                >
                  <%= for message <- @messages do %>
                    <div class="flex items-start space-x-3">
                      <img
                        src={message.user.avatar_path || "/images/profile_avatar.png"}
                        class="w-8 h-8 rounded-full"
                        alt={message.user.username}
                      />
                      <div class="flex-1">
                        <div class="flex items-center space-x-2">
                          <span class="text-sm font-medium text-gray-900">
                            {message.user.username}
                          </span>
                          <span class="text-xs text-gray-500">
                            {Timex.format!(message.inserted_at, "{h12}:{m} {AM}")}
                          </span>
                        </div>
                        <p class="text-gray-900 mt-1">
                          {message.body}
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>

    <!-- Message input -->
                <div class="border-t border-gray-200 bg-white p-4">
                  <.form
                    for={@message_form}
                    phx-submit="send_message"
                    phx-target={@myself}
                    class="flex space-x-4"
                  >
                    <input
                      type="text"
                      name="message[body]"
                      placeholder="Type a message..."
                      class="flex-1 border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                    <button
                      type="submit"
                      class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                      Send
                    </button>
                  </.form>
                </div>
              <% else %>
                <!-- Conversation list -->
                <div class="dm-messages-container flex-1 overflow-y-auto">
                  <div class="p-4 border-b border-gray-200">
                    <p class="text-sm text-gray-600">
                      {@unread_count} unread conversation{if @unread_count != 1, do: "s"}
                    </p>
                  </div>

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
                              {Timex.format!(conversation.last_message_at, "{relative}", :relative)}
                            <% else %>
                              No messages yet
                            <% end %>
                          </p>
                        </div>
                        <%= if get_unread_count(conversation, @current_user) > 0 do %>
                          <span class="ml-2 flex-shrink-0 bg-red-500 text-white text-xs font-medium
                                      px-2 py-1 rounded-full">
                            {get_unread_count(conversation, @current_user)}
                          </span>
                        <% end %>
                      </div>
                    </button>
                  <% end %>
                </div>

    <!-- Empty state -->
                <%= if Enum.empty?(@conversations) do %>
                  <div class="flex-1 flex items-center justify-center bg-gray-50">
                    <div class="text-center">
                      <div class="mx-auto h-12 w-12 text-gray-400">
                        <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" class="w-12 h-12">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="1"
                            d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                          />
                        </svg>
                      </div>
                      <h3 class="mt-2 text-sm font-medium text-gray-900">No conversations yet</h3>
                      <p class="mt-1 text-sm text-gray-500">
                        Start a new conversation by clicking the DM icon next to a user's name
                      </p>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%= if @selected_conversation do %>
        <script>
          // Scroll to bottom of messages container
          const messagesContainer = document.getElementById('messages-container');
          if (messagesContainer) {
            messagesContainer.scrollTop = messagesContainer.scrollHeight;
          }
        </script>
      <% end %>
    </div>
    """
  end

  defp conversation_title(conversation, current_user) do
    # Handle the case where conversation_participants might not be loaded
    conversation_participants =
      case conversation.conversation_participants do
        %Ecto.Association.NotLoaded{} -> []
        conversation_participants -> conversation_participants
      end

    other_participants =
      Enum.reject(conversation_participants, &(&1.user_id == current_user.id))
      |> Enum.map(fn participant ->
        case participant.user do
          %Ecto.Association.NotLoaded{} -> "Unknown User"
          user -> user.username
        end
      end)
      |> Enum.join(", ")

    if other_participants == "" do
      conversation.title || "Direct Messages"
    else
      "Conversation with #{other_participants}"
    end
  end

  defp get_unread_count(conversation, current_user) do
    case DirectMessaging.get_conversation_with_unread_count(current_user, conversation.id) do
      {_, count} -> count
      nil -> 0
    end
  end
end
