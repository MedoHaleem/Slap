defmodule SlapWeb.DirectMessagingComponent do
  use SlapWeb, :live_component

  alias Slap.DirectMessaging

  @impl true
  def update(assigns, socket) do
    # Assign all passed assigns first, excluding reserved assigns
    assigns = Map.drop(assigns, [:myself])
    socket = assign(socket, assigns)

    # Handle direct_message_deleted event
    socket =
      if Phoenix.LiveView.connected?(socket) and Map.has_key?(assigns, :direct_message_deleted) do
        message = assigns.direct_message_deleted

        conversation = socket.assigns.selected_conversation

        if conversation && conversation.id == message.conversation_id do
          messages =
            Enum.reject(socket.assigns.messages, fn msg ->
              msg.id == message.id
            end)

          # Force a re-render by updating the messages assign
          assign(socket, messages: messages)
        else
          # If the message is not in the selected conversation, we still need to refresh the conversation list
          refresh_conversations(socket)
        end
      else
        socket
      end

    # Initialize required assigns only if not already present and connected
    socket =
      if Phoenix.LiveView.connected?(socket) do
        socket =
          if socket.assigns[:conversations] == nil do
            conversations =
              DirectMessaging.get_user_conversations_with_unread_counts(
                socket.assigns.current_user
              )

            assign(socket, conversations: conversations)
          else
            socket
          end

        # Initialize selected_conversation if not present
        socket =
          if socket.assigns[:selected_conversation] == nil do
            assign(socket, selected_conversation: nil)
          else
            socket
          end

        # Initialize messages if not present
        socket =
          if socket.assigns[:messages] == nil do
            assign(socket, messages: [])
          else
            socket
          end

        # Initialize message form
        socket =
          if socket.assigns[:message_form] == nil do
            assign(socket, message_form: to_form(%{"body" => ""}))
          else
            socket
          end

        # If we have a target user and no selected conversation, try to find or create a conversation
        socket =
          if socket.assigns[:target_user] && socket.assigns.selected_conversation == nil do
            current_user = socket.assigns.current_user
            target_user = socket.assigns.target_user

            case DirectMessaging.get_conversation_between_users(current_user.id, target_user.id) do
              nil ->
                # No conversation exists, create a new one
                case DirectMessaging.create_conversation(%{},
                       participants: [current_user, target_user]
                     ) do
                  {:ok, conversation} ->
                    DirectMessaging.subscribe_to_conversation(conversation)
                    DirectMessaging.mark_conversation_read(conversation, current_user)

                    messages =
                      DirectMessaging.list_direct_messages(conversation.id,
                        current_user_id: current_user.id
                      )

                    socket
                    |> assign(selected_conversation: conversation, messages: messages)
                    |> refresh_conversations()

                  {:error, _} ->
                    socket
                end

              conversation ->
                # Conversation exists, use it
                DirectMessaging.subscribe_to_conversation(conversation)
                DirectMessaging.mark_conversation_read(conversation, current_user)

                messages =
                  DirectMessaging.list_direct_messages(conversation.id,
                    current_user_id: current_user.id
                  )

                socket
                |> assign(selected_conversation: conversation, messages: messages)
                |> refresh_conversations()
            end
          else
            socket
          end

        schedule_heartbeat(socket)
      else
        # Initialize default values when not connected
        socket =
          if socket.assigns[:selected_conversation] == nil do
            assign(socket, selected_conversation: nil)
          else
            socket
          end

        socket =
          if socket.assigns[:messages] == nil do
            assign(socket, messages: [])
          else
            socket
          end

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

        messages =
          DirectMessaging.list_direct_messages(conversation.id, current_user_id: current_user.id)

        socket =
          socket
          |> assign(selected_conversation: conversation, messages: messages)
          |> refresh_conversations()

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

  def handle_event("reconnect", %{"last_message_id" => last_id}, socket) do
    conversation = socket.assigns.selected_conversation
    current_user = socket.assigns.current_user

    if conversation do
      # Fetch missed messages since last_id
      missed_messages =
        DirectMessaging.get_messages_since(conversation.id, last_id,
          current_user_id: current_user.id
        )

      {:noreply, assign(socket, :missed_messages, missed_messages)}
    else
      {:noreply, socket}
    end
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
      # Update conversations with new unread counts
      {:noreply, refresh_conversations(socket)}
    end
  end

  def handle_info({:direct_message_deleted, message}, socket) do
    conversation = socket.assigns.selected_conversation

    if conversation && conversation.id == message.conversation_id do
      messages =
        Enum.reject(socket.assigns.messages, fn msg ->
          msg.id == message.id
        end)

      # Force a re-render by updating the messages assign
      {:noreply, assign(socket, messages: messages)}
    else
      # If the message is not in the selected conversation, we still need to refresh the conversation list
      {:noreply, refresh_conversations(socket)}
    end
  end

  def handle_info({:conversation_read, user_id, _timestamp}, socket) do
    current_user = socket.assigns.current_user

    if user_id != current_user.id do
      # Update conversations with refreshed unread counts when other participants read messages
      {:noreply, refresh_conversations(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:conversation_deleted, conversation_id}, socket) do
    selected_conversation = socket.assigns.selected_conversation

    socket =
      if selected_conversation && selected_conversation.id == conversation_id do
        # If the deleted conversation is currently selected, clear the selection
        assign(socket, selected_conversation: nil, messages: [])
      else
        socket
      end

    # Remove the deleted conversation from the list and refresh
    {:noreply, refresh_conversations(socket)}
  end

  def handle_info(:heartbeat, socket) do
    # Send heartbeat to client and schedule next heartbeat
    socket = schedule_heartbeat(socket)
    {:noreply, push_event(socket, "heartbeat", %{timestamp: DateTime.utc_now()})}
  end

  def handle_info(:close_dm_panel, socket) do
    send(self(), :close_dm_panel)
    {:noreply, socket}
  end

  defp schedule_heartbeat(socket) do
    # Send heartbeat every 30 seconds
    Process.send_after(self(), :heartbeat, 30_000)
    socket
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
                            {Timex.format!(message.inserted_at, "%I:%M %p", :strftime)}
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

  defp refresh_conversations(socket) do
    conversations =
      DirectMessaging.get_user_conversations_with_unread_counts(socket.assigns.current_user)

    assign(socket, conversations: conversations)
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

  defp get_unread_count(conversation, _current_user) do
    # Use the pre-calculated unread count from the optimized query
    Map.get(conversation, :unread_count, 0)
  end
end
