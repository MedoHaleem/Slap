# LiveView Components

This document provides a comprehensive overview of the LiveView components in the Slap application, including their functionality, state management, and event handling.

## Overview

Slap uses Phoenix LiveView extensively to provide real-time functionality with minimal client-side JavaScript. The LiveView components handle:

- Real-time messaging
- User authentication
- Direct messaging
- Voice chat
- Search functionality
- File uploads

## Core LiveView Components

### ChatRoomLive

**Location**: [`lib/slap_web/live/chat_room_live.ex`](../../lib/slap_web/live/chat_room_live.ex)

The main chat interface that handles room-based messaging.

#### State Management

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(:current_user, socket.assigns.current_user)
    |> assign(:room, nil)
    |> assign(:messages, [])
    |> assign(:page, 1)
    |> assign(:has_more_messages, true)
    |> assign(:search_query, "")
    |> assign(:search_results, [])
    |> assign(:show_search, false)
    |> assign(:show_thread, false)
    |> assign(:thread_message, nil)
    |> assign(:thread_replies, [])
    |> assign(:show_dm_panel, false)
    |> assign(:unread_counts, %{})
  
  {:ok, socket}
end
```

#### Key Events

- `"submit-message"`: Send a new message
- `"delete-message"`: Delete a message
- `"add-reaction"`: Add emoji reaction
- `"remove-reaction"`: Remove emoji reaction
- `"search"`: Search messages
- `"show-thread"`: Show message thread
- `"start-direct-message"`: Start direct message conversation
- `"accept-call"`: Accept voice call
- `"reject-call"`: Reject voice call

#### Real-time Updates

```elixir
def handle_info({:new_message, message}, socket) do
  socket =
    socket
    |> update(:messages, fn messages -> [message | messages] end)
    |> maybe_update_unread_count(message.room_id)
  
  {:noreply, socket}
end
```

### DirectMessagingComponent

**Location**: [`lib/slap_web/live/direct_messaging_component.ex`](../../lib/slap_web/live/direct_messaging_component.ex)

Handles direct messaging functionality with support for one-on-one and group conversations.

#### State Management

```elixir
def update(assigns, socket) do
  socket =
    socket
    |> assign(:current_user, assigns.current_user)
    |> assign(:conversations, get_user_conversations(assigns.current_user))
    |> assign(:selected_conversation, nil)
    |> assign(:messages, [])
    |> assign(:page, 1)
    |> assign(:has_more_messages, true)
    |> assign(:form, to_form(%{"body" => ""}))
    |> assign(:show_group_form, false)
    |> assign(:show_invite_form, false)
    |> assign(:unread_counts, %{})
  
  {:ok, socket}
end
```

#### Key Events

- `"select_conversation"`: Select a conversation to view
- `"send_message"`: Send a direct message
- `"create_group_conversation"`: Create new group conversation
- `"invite_user"`: Invite user to group conversation
- `"leave_conversation"`: Leave a conversation
- `"promote_participant"`: Promote participant to admin/moderator
- `"accept_invitation"`: Accept conversation invitation

### VoiceChatLive

**Location**: [`lib/slap_web/live/voice_chat_live.ex`](../../lib/slap_web/live/voice_chat_live.ex)

Manages voice calls using WebRTC for peer-to-peer audio communication.

#### State Management

```elixir
def mount(%{"target_user_id" => target_user_id_param}, _session, socket) do
  target_user_id = String.to_integer(target_user_id_param)
  
  socket =
    socket
    |> assign(:current_user, socket.assigns.current_user)
    |> assign(:target_user_id, target_user_id)
    |> assign(:call_status, :idle)
    |> assign(:local_stream, nil)
    |> assign(:remote_stream, nil)
    |> assign(:error_message, nil)
    |> setup_voice_channel()
  
  {:ok, socket}
end
```

#### Call States

- `:idle`: No active call
- `:calling`: Initiating a call
- `:ringing`: Call is ringing for recipient
- `:connecting`: Call is being established
- `:connected`: Active call in progress
- `:ended`: Call has ended

#### Key Events

- `"request_call"`: Initiate a voice call
- `"accept_call"`: Accept incoming call
- `"reject_call"`: Reject incoming call
- `"end_call"`: End active call
- `"signal"`: WebRTC signaling message

### MessageSearchLive

**Location**: [`lib/slap_web/live/message_search_live.ex`](../../lib/slap_web/live/message_search_live.ex)

Provides search functionality across messages and direct messages.

#### State Management

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(:query, "")
    |> assign(:results, [])
    |> assign(:page, 1)
    |> assign(:total_pages, 0)
    |> assign(:total_count, 0)
    |> assign(:search_type, "all")
    |> assign(:room_id, nil)
    |> assign(:conversation_id, nil)
  
  {:ok, socket}
end
```

#### Key Events

- `"search"`: Perform search with query
- `"next_page"`: Navigate to next page of results
- `"previous_page"`: Navigate to previous page of results

## Authentication LiveViews

### UserRegistrationLive

**Location**: [`lib/slap_web/live/user_registration_live.ex`](../../lib/slap_web/live/user_registration_live.ex)

Handles new user registration with validation and email confirmation.

#### State Management

```elixir
def mount(_params, _session, socket) do
  changeset = Accounts.change_user_registration(%User{})
  
  socket =
    socket
    |> assign(:changeset, changeset)
    |> assign(:trigger_submit, false)
  
  {:ok, socket}
end
```

#### Key Events

- `"save"`: Submit registration form
- `"validate"`: Validate form in real-time

### UserLoginLive

**Location**: [`lib/slap_web/live/user_login_live.ex`](../../lib/slap_web/live/user_login_live.ex)

Handles user authentication with remember me functionality.

#### Key Events

- `"save"`: Submit login form

### UserSettingsLive

**Location**: [`lib/slap_web/live/user_settings_live.ex`](../../lib/slap_web/live/user_settings_live.ex)

Manages user profile settings including email, password, and avatar.

#### State Management

```elixir
def mount(%{"token" => token}, _session, socket) do
  socket =
    socket
    |> assign(:current_user, socket.assigns.current_user)
    |> assign(:email_changeset, Accounts.change_user_email(current_user))
    |> assign(:password_changeset, Accounts.change_user_password(current_user))
    |> assign(:trigger_submit, false)
  
  {:ok, socket}
end
```

#### Key Events

- `"validate_email"`: Validate email change form
- `"update_email"`: Submit email change
- `"validate_password"`: Validate password change form
- `"update_password"`: Submit password change
- `"submit-avatar"`: Upload avatar image

## Chat Room Subcomponents

### MessageListComponent

**Location**: [`lib/slap_web/live/chat_room_live/message_list_component.ex`](../../lib/slap_web/live/chat_room_live/message_list_component.ex)

Displays messages with pagination and date dividers.

#### Features

- Message pagination with "load more" functionality
- Date dividers for message organization
- Unread message markers
- Auto-scroll to new messages

### MessageFormComponent

**Location**: [`lib/slap_web/live/chat_room_live/message_form_component.ex`](../../lib/slap_web/live/chat_room_live/message_form_component.ex)

Handles message composition and file uploads.

#### Features

- Auto-resizing text area
- File upload with progress tracking
- Form validation
- Emoji picker (future feature)

### SidebarComponent

**Location**: [`lib/slap_web/live/chat_room_live/sidebar_component.ex`](../../lib/slap_web/live/chat_room_live/sidebar_component.ex)

Displays room list, user presence, and direct messaging access.

#### Features

- Room list with unread counts
- Online user presence
- Direct messaging integration
- Room navigation

### ThreadComponent

**Location**: [`lib/slap_web/live/chat_room_live/thread_component.ex`](../../lib/slap_web/live/chat_room_live/thread_component.ex)

Displays and manages message threads/replies.

#### Features

- Reply creation and display
- Thread navigation
- Reply notifications

## Component Communication

### Parent-Child Communication

Components communicate through assigns and events:

```elixir
# Parent sends data to child
<.live_component 
  module={MessageFormComponent} 
  id="message-form"
  current_user={@current_user}
  room={@room}
/>

# Child sends event to parent
push_event("send_message", %{body: message_body})
```

### PubSub Communication

Components communicate via Phoenix PubSub for real-time updates:

```elixir
# Broadcast message update
Phoenix.PubSub.broadcast(
  Slap.PubSub,
  "chat_room:#{room_id}",
  {:new_message, message}
)

# Receive message update
def handle_info({:new_message, message}, socket) do
  # Update UI
end
```

## Component Lifecycle

### Mount

Components are mounted with initial state:

```elixir
def mount(params, session, socket) do
  # Initialize state
  # Subscribe to channels
  # Perform initial data loading
  {:ok, socket}
end
```

### Update

Components update when assigns change:

```elixir
def update(assigns, socket) do
  # React to assign changes
  # Update internal state
  {:ok, socket}
end
```

### Handle Events

Components handle user interactions:

```elixir
def handle_event("event_name", params, socket) do
  # Process event
  # Update state
  # Broadcast changes
  {:noreply, socket}
end
```

### Handle Info

Components handle server-sent messages:

```elixir
def handle_info(message, socket) do
  # Process server message
  # Update UI
  {:noreply, socket}
end
```

## Performance Optimizations

### Efficient State Updates

Components use efficient state updates:

```elixir
# Good: Update specific field
assign(socket, :messages, [new_message | messages])

# Avoid: Reassigning entire state
assign(socket, :state, %{state | messages: [new_message | messages]})
```

### Stream Operations

Large datasets use streams for performance:

```elixir
stream(socket, :messages, messages, reset: true)
```

### Debounced Events

Frequent events are debounced:

```elixir
def handle_event("search", %{"query" => query}, socket) do
  # Debounced search
  Process.send_after(self(), :perform_search, 300)
  {:noreply, assign(socket, :query, query)}
end
```

## Error Handling

### Component Errors

Components handle errors gracefully:

```elixir
def handle_event("submit-message", %{"message" => message_params}, socket) do
  case create_message(message_params, socket.assigns.current_user) do
    {:ok, message} ->
      # Handle success
      {:noreply, socket}
    
    {:error, changeset} ->
      # Handle error
      socket =
        socket
        |> assign(:changeset, changeset)
        |> put_flash(:error, "Failed to send message")
      
      {:noreply, socket}
  end
end
```

### Validation Errors

Form validation errors are displayed:

```elixir
<.input 
  field={@changeset[:body]} 
  type="textarea" 
  errors={@changeset.errors}
/>
```

## Testing LiveView Components

### Unit Tests

```elixir
defmodule SlapWeb.ChatRoomLiveTest do
  use SlapWeb.ConnCase
  
  test "mounts chat room with messages", %{conn: conn} do
    user = user_fixture()
    room = room_fixture()
    message = message_fixture(room, user)
    
    {:ok, view, _html} = live(conn, "/rooms/#{room.id}")
    
    assert render(view) =~ room.name
    assert render(view) =~ message.body
  end
  
  test "sends message", %{conn: conn} do
    user = user_fixture()
    room = room_fixture()
    
    {:ok, view, _html} = live(conn, "/rooms/#{room.id}")
    
    view
    |> form("#message-form", message: %{body: "Test message"})
    |> render_submit()
    
    assert render(view) =~ "Test message"
  end
end
```

### Integration Tests

```elixir
test "real-time message updates", %{conn: conn} do
  user1 = user_fixture()
  user2 = user_fixture()
  room = room_fixture()
  
  {:ok, view1, _html} = live(log_in_user(conn, user1), "/rooms/#{room.id}")
  {:ok, view2, _html} = live(log_in_user(build_conn(), user2), "/rooms/#{room.id}")
  
  # User1 sends message
  view1
  |> form("#message-form", message: %{body: "Hello from user1"})
  |> render_submit()
  
  # User2 sees message
  assert render(view2) =~ "Hello from user1"
end
```

## Best Practices

### Component Design

- Keep components focused on single responsibilities
- Use clear and descriptive function names
- Document public functions with @doc annotations
- Handle errors gracefully with user feedback

### State Management

- Minimize state stored in components
- Use assigns for derived data
- Avoid storing large datasets in component state
- Use streams for large collections

### Performance

- Use efficient update patterns
- Debounce frequent events
- Paginate large datasets
- Optimize database queries

### Security

- Validate all user input
- Authorize actions before execution
- Use secure channel subscriptions
- Sanitize rendered content

This LiveView component documentation provides a comprehensive overview of the real-time UI components that power the Slap application, making it easier for developers to understand and extend the functionality.