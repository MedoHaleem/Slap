# DirectMessagingComponent Refactoring Guide

This guide provides specific instructions for refactoring the DirectMessagingComponent to use the new shared modules and break it down into smaller, focused components.

## Overview

The DirectMessagingComponent (`lib/slap_web/live/direct_messaging_component.ex`) is nearly 1,000 lines and handles multiple responsibilities:

1. Conversation management
2. Message rendering
3. Group settings
4. Participant management
5. Invitation handling

## Step-by-Step Refactoring

### 1. Add Imports and Replace Constants

**Add these imports at the top of the file:**

```elixir
import SlapWeb.UIHelpers
alias Slap.{Constants, Authorization, ErrorHandler}
```

**Replace CSS classes and constants:**

```elixir
# Replace button classes
<.primary_button phx-click="send_message">Send</.primary_button>
<.secondary_button phx-click="close_dm">Close</.secondary_button>
<.danger_button phx-click="leave_conversation">Leave</.danger_button>

# Replace avatar rendering
<.user_avatar user={message.user} size="normal" />

# Replace unread badge
<.unread_badge count={unread_count} />

# Replace role badge
<.role_badge role={participant.role} />

# Replace error messages
def handle_event("create_group_conversation", _params, socket) do
  case DirectMessaging.create_group_conversation(...) do
    {:ok, _} -> # Success
    {:error, _reason} -> 
      put_flash(socket, :error, Constants.get_error_message(:conversation_creation_failed))
  end
end
```

### 2. Replace Error Handling

**Update error handling throughout the component:**

```elixir
# Wrap event handlers with error handling
def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
  ErrorHandler.with_error_handling(fn ->
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    case DirectMessaging.send_direct_message(conversation, %{body: body}, current_user) do
      {:ok, message} ->
        socket =
          socket
          |> assign(message_form: to_form(%{"body" => ""}))
          |> assign(messages: [message | socket.assigns.messages])

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, ErrorHandler.normalize_error(changeset))}
    end
  end, user_id: socket.assigns.current_user.id)
end
```

### 3. Replace Permission Checking

**Update permission checks:**

```elixir
# Replace permission checks
defp can_manage_conversation?(conversation, current_user) do
  Authorization.can_manage_conversation?(current_user, conversation)
end

defp can_invite_to_conversation?(conversation, current_user) do
  Authorization.can_invite_to_conversation?(current_user, conversation)
end

# Update event handlers
def handle_event("update_conversation_title", %{"title" => title}, socket) do
  current_user = socket.assigns.current_user
  conversation = socket.assigns.selected_conversation

  if Authorization.can_manage_conversation?(current_user, conversation) do
    case DirectMessaging.update_conversation(conversation, %{title: title}) do
      {:ok, updated_conversation} ->
        {:noreply, assign(socket, selected_conversation: updated_conversation)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, Constants.get_error_message(:conversation_update_failed))}
    end
  else
    {:noreply, put_flash(socket, :error, Constants.get_error_message(:insufficient_permissions))}
  end
end
```

### 4. Extract Conversation List Component

**Create a new component for the conversation list:**

```elixir
# Create lib/slap_web/live/direct_messaging/conversation_list_component.ex
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
                  {format_timestamp(conversation.last_message_at)}
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

  defp format_timestamp(timestamp) do
    if function_exported?(Timex, :format, 2) do
      Timex.format!(timestamp, "{relative}")
    else
      Calendar.strftime(timestamp, Constants.message_timestamp_format())
    end
  end
end
```

### 5. Extract Message List Component

**Create a new component for the message list:**

```elixir
# Create lib/slap_web/live/direct_messaging/message_list_component.ex
defmodule SlapWeb.DirectMessaging.MessageListComponent do
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
    <div
      class="dm-messages-container flex-1 overflow-y-auto p-4 space-y-4"
      id="messages-container"
    >
      <%= for message <- @messages do %>
        <.message_container>
          <.user_avatar user={message.user} size="normal" />
          <.message_content>
            <div class="flex items-center space-x-2">
              <span class="text-sm font-medium text-gray-900">
                {message.user.username}
              </span>

              <.message_timestamp timestamp={message.inserted_at} />
            </div>

            <.message_body body={message.body} />
          </.message_content>
        </.message_container>
      <% end %>
    </div>

    <script>
      // Scroll to bottom of messages container
      const messagesContainer = document.getElementById('messages-container');
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    </script>
    """
  end
end
```

### 6. Extract Message Form Component

**Create a new component for the message form:**

```elixir
# Create lib/slap_web/live/direct_messaging/message_form_component.ex
defmodule SlapWeb.DirectMessaging.MessageFormComponent do
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
    <div class="border-t border-gray-200 bg-white p-4">
      <.form
        for={@message_form}
        phx-submit="send_message"
        phx-target={@myself}
        class="flex space-x-4"
      >
        <.form_input
          type="text"
          name="message[body]"
          placeholder="Type a message..."
          class="flex-1"
        />
        <.primary_button type="submit">Send</.primary_button>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    case DirectMessaging.send_direct_message(conversation, %{body: body}, current_user) do
      {:ok, message} ->
        send(self(), {:new_message, message})
        {:reply, %{message_form: to_form(%{"body" => ""})}, socket}

      {:error, _changeset} ->
        {:reply, %{error: Constants.get_error_message(:message_send_failed)}}, socket}
    end
  end
end
```

### 7. Extract Group Settings Component

**Create a new component for group settings:**

```elixir
# Create lib/slap_web/live/direct_messaging/group_settings_component.ex
defmodule SlapWeb.DirectMessaging.GroupSettingsComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers
  alias Slap.{Constants, Authorization}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-3 border-t border-gray-100 pt-3">
      <h4 class="text-sm font-medium text-gray-700 mb-2">Conversation Settings</h4>
      <form phx-submit="update_conversation_title" phx-target={@myself} class="space-y-3">
        <div>
          <label class="block text-xs text-gray-600">Conversation Title</label>
          <.form_input
            type="text"
            name="title"
            value={@conversation.title}
          />
        </div>
        <.success_button type="submit">Update Title</.success_button>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("update_conversation_title", %{"title" => title}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    if Authorization.can_manage_conversation?(current_user, conversation) do
      case DirectMessaging.update_conversation(conversation, %{title: title}) do
        {:ok, updated_conversation} ->
          send(self(), {:conversation_updated, updated_conversation})
          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, Constants.get_error_message(:conversation_update_failed))}
      end
    else
      {:noreply, put_flash(socket, :error, Constants.get_error_message(:insufficient_permissions))}
    end
  end
end
```

### 8. Extract Participant List Component

**Create a new component for the participant list:**

```elixir
# Create lib/slap_web/live/direct_messaging/participant_list_component.ex
defmodule SlapWeb.DirectMessaging.ParticipantListComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers
  alias Slap.{Constants, Authorization}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-3 border-t border-gray-100 pt-3">
      <h4 class="text-sm font-medium text-gray-700 mb-2">Participants</h4>
      <div class="space-y-2 max-h-32 overflow-y-auto">
        <%= for participant <- @conversation.conversation_participants do %>
          <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
            <div class="flex items-center space-x-2">
              <.user_avatar user={participant.user} size="small" />
              <span class="text-sm text-gray-900">
                {participant.user.username}
              </span>
              <.role_badge role={participant.role} />
            </div>

            <%= if Authorization.can_manage_participants?(@current_user, @conversation) &&
                  participant.user_id != @current_user.id do %>
              <div class="flex items-center space-x-1">
                <select
                  class="text-xs border border-gray-300 rounded px-1 py-0.5"
                  phx-change="promote_participant"
                  phx-value-user-id={participant.user_id}
                  phx-target={@myself}
                >
                  <option value="member" selected={participant.role == "member"}>Member</option>
                  <option value="moderator" selected={participant.role == "moderator"}>Moderator</option>
                  <option value="admin" selected={participant.role == "admin"}>Admin</option>
                </select>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("promote_participant", %{"user_id" => user_id, "role" => new_role}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    if Authorization.can_manage_participants?(current_user, conversation) do
      case DirectMessaging.promote_participant(conversation, String.to_integer(user_id), new_role, current_user) do
        {:ok, _participant} ->
          send(self(), {:participants_updated})
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    else
      {:noreply, put_flash(socket, :error, Constants.get_error_message(:insufficient_permissions))}
    end
  end
end
```

### 9. Update Main DirectMessagingComponent

**Update the main component to use the extracted components:**

```elixir
defmodule SlapWeb.DirectMessagingComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers
  alias Slap.{Constants, Authorization, ErrorHandler}

  # Extracted components
  alias SlapWeb.DirectMessaging.{
    ConversationListComponent,
    MessageListComponent,
    MessageFormComponent,
    GroupSettingsComponent,
    ParticipantListComponent
  }

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
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
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
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                          </svg>
                        </button>
                      <% end %>
                    </div>
                  </div>

                  <!-- Participants Panel -->
                  <%= if @show_participants && is_group_conversation?(@selected_conversation) do %>
                    <.live_component
                      module={ParticipantListComponent}
                      id="participants"
                      conversation={@selected_conversation}
                      current_user={@current_user}
                    />
                  <% end %>

                  <!-- Settings Panel -->
                  <%= if @show_group_settings && Authorization.can_manage_conversation?(@current_user, @selected_conversation) do %>
                    <.live_component
                      module={GroupSettingsComponent}
                      id="group-settings"
                      conversation={@selected_conversation}
                      current_user={@current_user}
                    />
                  <% end %>
                </div>

                <!-- Messages list -->
                <.live_component
                  module={MessageListComponent}
                  id="message-list"
                  messages={@messages}
                />

                <!-- Message input -->
                <.live_component
                  module={MessageFormComponent}
                  id="message-form"
                  conversation={@selected_conversation}
                  current_user={@current_user}
                />
              <% else %>
                <!-- Conversation list -->
                <.live_component
                  module={ConversationListComponent}
                  id="conversation-list"
                  conversations={@conversations}
                  selected_conversation={@selected_conversation}
                  current_user={@current_user}
                />
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Update handle_info to work with extracted components
  def handle_info({:new_message, message}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.selected_conversation

    if conversation && conversation.id == message.conversation_id do
      # Only add the message if it wasn't sent by the current user
      if message.user_id != current_user.id do
        messages = [message | socket.assigns.messages]
        socket = assign(socket, messages: messages)
        
        # Send update to MessageListComponent
        send_update(MessageListComponent, id: "message-list", messages: messages)
      end

      {:noreply, socket}
    else
      # Update conversations list
      send_update(ConversationListComponent, id: "conversation-list", refresh: true)
      {:noreply, socket}
    end
  end

  # Update other handle_info functions similarly
  # ...

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

  defp is_group_conversation?(conversation) do
    conversation.type == "group"
  end
end
```

## Testing the Refactored Components

After making these changes:

1. **Run the DirectMessagingComponent tests**:
   ```bash
   mix test test/slap_web/live/direct_messaging_component_test.exs
   ```

2. **Run the integration tests**:
   ```bash
   mix test test/slap_web/live/end_to_end_dm_test.exs
   ```

3. **Check for compilation errors**:
   ```bash
   mix compile
   ```

4. **Test the specific functionality**:
   - Conversation selection
   - Message sending
   - Group settings
   - Participant management

## Expected Benefits

After refactoring:

1. **Reduced component size** from nearly 1,000 lines to approximately 200-300 lines
2. **Improved maintainability** with smaller, focused components
3. **Better reusability** of UI components
4. **Easier testing** with isolated components
5. **Consistent UI** with shared components

## Conclusion

This refactoring guide provides specific instructions for breaking down the DirectMessagingComponent into smaller, focused components using the shared modules. By following these steps, we can significantly reduce the complexity of the component while preserving all existing functionality.