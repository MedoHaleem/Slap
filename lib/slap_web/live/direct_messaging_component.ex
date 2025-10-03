defmodule SlapWeb.DirectMessagingComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers
  alias Slap.{Constants, Authorization}
  alias Slap.DirectMessaging

  # Extracted components
  # Note: These aliases are not used in this file as the functionality is implemented directly

  require Logger

  @impl true
  def update(assigns, socket) do
    # Assign all passed assigns first, excluding reserved assigns
    assigns = Map.drop(assigns, [:myself])
    socket = assign(socket, assigns)

    # Handle events
    socket = handle_direct_message_deleted_event(socket, assigns)
    socket = handle_dm_action_event(socket, assigns)

    # Initialize state
    socket = initialize_state(socket, Phoenix.LiveView.connected?(socket))

    {:ok, socket}
  end

  # Extract direct message deleted event handling
  defp handle_direct_message_deleted_event(socket, assigns) do
    if Phoenix.LiveView.connected?(socket) and Map.has_key?(assigns, :direct_message_deleted) do
      message = assigns.direct_message_deleted
      conversation = socket.assigns.selected_conversation

      if conversation && conversation.id == message.conversation_id do
        messages = Enum.reject(socket.assigns.messages, fn msg -> msg.id == message.id end)
        assign(socket, messages: messages)
      else
        # If the message is not in the selected conversation, we still need to refresh the conversation list
        refresh_conversations(socket)
      end
    else
      socket
    end
  end

  # Extract dm action event handling
  defp handle_dm_action_event(socket, assigns) do
    if Phoenix.LiveView.connected?(socket) and Map.has_key?(assigns, :dm_action) and
         assigns.dm_action do
      socket = handle_dm_action(socket, assigns.dm_action)
      # Clear the dm_action after processing to prevent repeated execution
      assign(socket, dm_action: nil)
    else
      socket
    end
  end

  # Extract state initialization logic
  defp initialize_state(socket, connected?) do
    if connected? do
      socket
      |> initialize_conversations()
      |> initialize_selected_conversation()
      |> initialize_messages()
      |> initialize_message_form()
      |> initialize_group_settings()
      |> initialize_participants()
      |> initialize_current_user_role()
      |> initialize_creating_group()
      |> handle_target_user_conversation()
      |> initialize_target_user()
      |> update_current_user_role()
      |> schedule_heartbeat()
    else
      # Initialize default values when not connected
      socket
      |> initialize_selected_conversation()
      |> initialize_messages()
    end
  end

  # Extract conversation initialization
  defp initialize_conversations(socket) do
    if socket.assigns[:conversations] == nil do
      conversations =
        DirectMessaging.get_user_conversations_with_unread_counts(socket.assigns.current_user)

      assign(socket, conversations: conversations)
    else
      socket
    end
  end

  # Extract selected conversation initialization
  defp initialize_selected_conversation(socket) do
    if socket.assigns[:selected_conversation] == nil do
      assign(socket, selected_conversation: nil)
    else
      socket
    end
  end

  # Extract messages initialization
  defp initialize_messages(socket) do
    if socket.assigns[:messages] == nil do
      assign(socket, messages: [])
    else
      socket
    end
  end

  # Extract message form initialization
  defp initialize_message_form(socket) do
    if socket.assigns[:message_form] == nil do
      assign(socket, message_form: to_form(%{"body" => ""}))
    else
      socket
    end
  end

  # Extract group settings initialization
  defp initialize_group_settings(socket) do
    if socket.assigns[:show_group_settings] == nil do
      assign(socket, show_group_settings: false)
    else
      socket
    end
  end

  # Extract participants initialization
  defp initialize_participants(socket) do
    if socket.assigns[:show_participants] == nil do
      assign(socket, show_participants: false)
    else
      socket
    end
  end

  # Extract current user role initialization
  defp initialize_current_user_role(socket) do
    if socket.assigns[:current_user_role] == nil do
      assign(socket, current_user_role: nil)
    else
      socket
    end
  end

  # Extract creating group initialization
  defp initialize_creating_group(socket) do
    if socket.assigns[:creating_group] == nil do
      assign(socket, creating_group: false)
    else
      socket
    end
  end

  # Extract target user initialization
  defp initialize_target_user(socket) do
    if !socket.assigns[:target_user] do
      assign(socket, target_user: nil)
    else
      socket
    end
  end

  # Extract target user conversation handling
  defp handle_target_user_conversation(socket) do
    if socket.assigns[:target_user] && socket.assigns.selected_conversation == nil do
      current_user = socket.assigns.current_user
      target_user = socket.assigns.target_user

      case DirectMessaging.get_conversation_between_users(current_user.id, target_user.id) do
        nil ->
          # No conversation exists, create a new one
          create_or_find_conversation(socket, current_user, target_user, :create)

        conversation ->
          # Conversation exists, use it
          create_or_find_conversation(socket, current_user, target_user, :find, conversation)
      end
    else
      socket
    end
  end

  # Extract conversation creation or finding logic
  defp create_or_find_conversation(socket, current_user, target_user, action, conversation \\ nil) do
    case action do
      :create ->
        case DirectMessaging.create_direct_message_conversation(%{}, current_user, target_user) do
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

      :find ->
        DirectMessaging.subscribe_to_conversation(conversation)
        DirectMessaging.mark_conversation_read(conversation, current_user)

        messages =
          DirectMessaging.list_direct_messages(conversation.id, current_user_id: current_user.id)

        socket
        |> assign(selected_conversation: conversation, messages: messages)
        |> refresh_conversations()
    end
  end

  # Extract current user role update logic
  defp update_current_user_role(socket) do
    if socket.assigns.selected_conversation do
      case DirectMessaging.get_user_role_in_conversation(
             socket.assigns.selected_conversation.id,
             socket.assigns.current_user.id
           ) do
        {:ok, role} -> assign(socket, current_user_role: role)
        {:error, _} -> assign(socket, current_user_role: nil)
      end
    else
      socket
    end
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
        {:noreply, put_flash(socket, :error, Constants.get_error_message(:message_send_failed))}
    end
  end

  @impl true
  def handle_event("close_dm", _params, socket) do
    send(self(), :close_dm_panel)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_group_settings", _params, socket) do
    {:noreply, assign(socket, show_group_settings: !socket.assigns.show_group_settings)}
  end

  @impl true
  def handle_event("toggle_participants", _params, socket) do
    {:noreply, assign(socket, show_participants: !socket.assigns.show_participants)}
  end

  @impl true
  def handle_event("create_group_conversation", _params, socket) do
    current_user = socket.assigns.current_user

    # Prevent rapid repeated clicks by checking if we're already processing
    if socket.assigns[:creating_group] do
      {:noreply, socket}
    else
      # Mark as creating to prevent duplicate requests
      socket = assign(socket, creating_group: true)

      case DirectMessaging.create_group_conversation(
             %{title: "New Group", is_public: false},
             [current_user],
             current_user
           ) do
        {:ok, conversation} ->
          DirectMessaging.subscribe_to_conversation(conversation)
          DirectMessaging.mark_conversation_read(conversation, current_user)

          messages =
            DirectMessaging.list_direct_messages(conversation.id,
              current_user_id: current_user.id
            )

          socket =
            socket
            |> assign(
              selected_conversation: conversation,
              messages: messages,
              creating_group: false
            )
            |> refresh_conversations()

          {:noreply, socket}

        {:error, reason} ->
          Logger.error("Failed to create group conversation: #{inspect(reason)}")

          {:noreply,
           put_flash(socket, :error, Constants.get_error_message(:conversation_creation_failed))
           |> assign(creating_group: false)}
      end
    end
  end

  @impl true
  def handle_event("update_conversation_title", %{"title" => title}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    if Authorization.can_manage_conversation?(current_user, conversation) do
      case DirectMessaging.update_conversation(conversation, %{title: title}) do
        {:ok, updated_conversation} ->
          {:noreply, assign(socket, selected_conversation: updated_conversation)}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, Constants.get_error_message(:conversation_update_failed))}
      end
    else
      {:noreply,
       put_flash(socket, :error, Constants.get_error_message(:insufficient_permissions))}
    end
  end

  @impl true
  def handle_event("invite_user", %{"user_id" => invitee_id}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    case DirectMessaging.create_conversation_invite(
           conversation,
           String.to_integer(invitee_id),
           current_user
         ) do
      {:ok, _invite} ->
        {:noreply, put_flash(socket, :info, Constants.get_success_message(:invitation_sent))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, Constants.get_error_message(:invitation_send_failed))}
    end
  end

  @impl true
  def handle_event("leave_conversation", _params, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    case DirectMessaging.remove_participant_from_conversation(conversation, current_user.id) do
      {_count, nil} ->
        socket =
          socket
          |> assign(selected_conversation: nil, messages: [])
          |> refresh_conversations()

        {:noreply, put_flash(socket, :info, Constants.get_success_message(:conversation_left))}

      _error ->
        {:noreply,
         put_flash(socket, :error, Constants.get_error_message(:conversation_leave_failed))}
    end
  end

  @impl true
  def handle_event("promote_participant", %{"user_id" => user_id, "role" => new_role}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    case DirectMessaging.promote_participant(
           conversation,
           String.to_integer(user_id),
           new_role,
           current_user
         ) do
      {:ok, _participant} ->
        # Refresh conversation participants
        updated_conversation =
          DirectMessaging.get_conversation!(conversation.id)
          |> Slap.Repo.preload(conversation_participants: :user)

        {:noreply, assign(socket, selected_conversation: updated_conversation)}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, Constants.get_error_message(:participant_promotion_failed))}
    end
  end

  @impl true
  def handle_event("accept_invitation", %{"token" => token}, socket) do
    current_user = socket.assigns.current_user

    case DirectMessaging.accept_conversation_invite(token, current_user) do
      {:ok, _participant} ->
        socket = refresh_conversations(socket)
        {:noreply, put_flash(socket, :info, Constants.get_success_message(:invitation_accepted))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, Constants.get_error_message(:invitation_accept_failed))}
    end
  end

  @impl true
  def handle_event("decline_invitation", %{"token" => token}, socket) do
    current_user = socket.assigns.current_user

    case Slap.Repo.get_by(Slap.Chat.ConversationInvite,
           token: token,
           invitee_id: current_user.id,
           status: "pending"
         ) do
      nil ->
        {:noreply, put_flash(socket, :error, Constants.get_error_message(:invitation_not_found))}

      invite ->
        invite
        |> Slap.Chat.ConversationInvite.changeset(%{status: "declined"})
        |> Slap.Repo.update()

        {:noreply, put_flash(socket, :info, Constants.get_success_message(:invitation_declined))}
    end
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
    # Ensure minimal defaults for template rendering when render_component/2 is used
    # (render_component passes assigns directly and does not call the component's update/2)
    assigns = Map.put_new(assigns, :creating_group, false)

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
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <h3 class="text-md font-semibold text-gray-900">
                        {conversation_title(@selected_conversation, @current_user)}
                      </h3>
                      
                      <p class="text-xs text-gray-600">
                        {length(@selected_conversation.conversation_participants)} participants
                        <%= if is_group_conversation?(@selected_conversation) do %>
                          <span class="ml-2 bg-blue-100 text-blue-800 text-xs font-medium px-2 py-1 rounded-full">
                            Group
                          </span>
                        <% end %>
                      </p>
                    </div>
                    
                    <div class="flex items-center space-x-2">
                      <%= if is_group_conversation?(@selected_conversation) do %>
                        <button
                          phx-click="toggle_participants"
                          phx-target={@myself}
                          class="text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
                          title="View Participants"
                        >
                          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                            />
                          </svg>
                        </button>
                      <% end %>
                      
                      <%= if Authorization.can_manage_conversation?(@current_user, @selected_conversation) do %>
                        <button
                          phx-click="toggle_group_settings"
                          phx-target={@myself}
                          class="text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
                          title="Conversation Settings"
                        >
                          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                            />
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                            />
                          </svg>
                        </button>
                      <% end %>
                    </div>
                  </div>
                  
    <!-- Participants Panel -->
                  <%= if @show_participants && is_group_conversation?(@selected_conversation) do %>
                    <div class="mt-3 border-t border-gray-100 pt-3">
                      <h4 class="text-sm font-medium text-gray-700 mb-2">Participants</h4>
                      
                      <div class="space-y-2 max-h-32 overflow-y-auto">
                        <%= for participant <- @selected_conversation.conversation_participants do %>
                          <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
                            <div class="flex items-center space-x-2">
                              <.user_avatar user={participant.user} size="small" />
                              <span class="text-sm text-gray-900">
                                {participant.user.username}
                              </span>
                               <.role_badge role={participant.role} />
                            </div>
                            
                            <%= if Authorization.can_manage_participants?(@current_user, @selected_conversation) &&
                                 participant.user_id != @current_user.id do %>
                              <div class="flex items-center space-x-1">
                                <select
                                  class="text-xs border border-gray-300 rounded px-1 py-0.5"
                                  phx-change="promote_participant"
                                  phx-value-user-id={participant.user_id}
                                  phx-target={@myself}
                                >
                                  <option value="member" selected={participant.role == "member"}>
                                    Member
                                  </option>
                                  
                                  <option value="moderator" selected={participant.role == "moderator"}>
                                    Moderator
                                  </option>
                                  
                                  <option value="admin" selected={participant.role == "admin"}>
                                    Admin
                                  </option>
                                </select>
                              </div>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                      
                      <%= if Authorization.can_invite_to_conversation?(@current_user, @selected_conversation) do %>
                        <div class="mt-3">
                          <form phx-submit="invite_user" phx-target={@myself} class="flex space-x-2">
                            <input
                              type="number"
                              name="user_id"
                              placeholder="User ID to invite"
                              class="flex-1 text-sm border border-gray-300 rounded px-2 py-1"
                              required
                            />
                            <.secondary_button type="submit">Invite</.secondary_button>
                          </form>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  
    <!-- Settings Panel -->
                  <%= if @show_group_settings && Authorization.can_manage_conversation?(@current_user, @selected_conversation) do %>
                    <div class="mt-3 border-t border-gray-100 pt-3">
                      <h4 class="text-sm font-medium text-gray-700 mb-2">Conversation Settings</h4>
                      
                      <form
                        phx-submit="update_conversation_title"
                        phx-target={@myself}
                        class="space-y-3"
                      >
                        <div>
                          <label class="block text-xs text-gray-600">Conversation Title</label>
                          <input
                            type="text"
                            name="title"
                            value={@selected_conversation.title}
                            class="w-full text-sm border border-gray-300 rounded px-2 py-1"
                          />
                        </div>
                        
                        <.success_button type="submit">Update Title</.success_button>
                      </form>
                    </div>
                  <% end %>
                </div>
                
    <!-- Messages list -->
                <div
                  class="dm-messages-container flex-1 overflow-y-auto p-4 space-y-4"
                  id="messages-container"
                >
                  <%= for message <- @messages do %>
                    <div class="flex items-start space-x-3">
                      <.user_avatar user={get_message_user(message)} size="normal" />
                      <div class="flex-1">
                        <div class="flex items-center space-x-2">
                          <span class="text-sm font-medium text-gray-900">
                            {get_message_user(message).username}
                          </span>
                           <.message_timestamp timestamp={message.inserted_at} format="time" />
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
                    <.primary_button type="submit">Send</.primary_button>
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
                         <.unread_badge count={get_unread_count(conversation, @current_user)} />
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
                      
                      <.primary_button
                        phx-click="create_group_conversation"
                        phx-target={@myself}
                        disabled={@creating_group}
                        class="mt-3"
                      >
                        {if @creating_group, do: "Creating...", else: "Create Group Conversation"}
                      </.primary_button>
                    </div>
                  </div>
                <% end %>
                
    <!-- Pending Invitations -->
                <div class="border-t border-gray-200 bg-gray-50 p-4">
                  <h4 class="text-sm font-medium text-gray-700 mb-2">Pending Invitations</h4>
                  
                  <%= for invite <- get_user_pending_invites(@current_user) do %>
                    <div class="flex items-center justify-between p-2 bg-white rounded border mb-2">
                      <div class="flex-1">
                        <p class="text-sm font-medium text-gray-900">
                          {invite.conversation.title}
                        </p>
                        
                        <p class="text-xs text-gray-500">
                          Invited by {invite.inviter.username}
                        </p>
                      </div>
                      
                      <div class="flex space-x-2">
                        <.success_button
                          phx-click="accept_invitation"
                          phx-value-token={invite.token}
                          phx-target={@myself}
                          class="text-xs px-2 py-1"
                        >
                          Accept
                        </.success_button>
                        
                        <.secondary_button
                          phx-click="decline_invitation"
                          phx-value-token={invite.token}
                          phx-target={@myself}
                          class="text-xs px-2 py-1"
                        >
                          Decline
                        </.secondary_button>
                      </div>
                    </div>
                  <% end %>
                  
                  <%= if Enum.empty?(get_user_pending_invites(@current_user)) do %>
                    <p class="text-xs text-gray-500">No pending invitations</p>
                  <% end %>
                </div>
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

  defp is_group_conversation?(conversation) do
    conversation.type == "group"
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

  defp get_user_pending_invites(current_user) do
    DirectMessaging.get_user_pending_invites(current_user)
  end

  defp handle_dm_action(socket, :browse_groups) do
    # Handle browse groups action - show public conversations
    public_conversations = DirectMessaging.list_public_groups(socket.assigns.current_user)

    assign(socket,
      conversations: public_conversations,
      selected_conversation: nil,
      messages: []
    )
  end

  defp handle_dm_action(socket, :create_group) do
    # Handle create group action - trigger group creation
    current_user = socket.assigns.current_user

    case DirectMessaging.create_group_conversation(
           %{title: "New Group", is_public: false},
           [current_user],
           current_user
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

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to create group conversation")
    end
  end

  defp handle_dm_action(socket, nil) do
    # No action specified, return socket as-is
    socket
  end

  defp handle_dm_action(socket, _action) do
    # Unknown action, log and return socket
    socket
  end

  defp get_message_user(message) do
    case message.user do
      %Ecto.Association.NotLoaded{} ->
        # If user is not loaded, try to load it or return a default user
        # This is a fallback to prevent crashes
        %{username: "Unknown User", avatar_path: nil}

      user ->
        user
    end
  end
end
