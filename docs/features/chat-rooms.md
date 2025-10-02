# Chat Rooms

This document provides a comprehensive overview of the chat room functionality in Slap, including room management, real-time messaging, and related features.

## Overview

The chat room system allows users to:

- Create, edit, and delete chat rooms
- Join and leave rooms
- Send and receive real-time messages
- React to messages with emojis
- Create message threads
- Upload and share files
- Search within room messages

## Architecture

### Context Module

The chat room logic is centralized in the [`Slap.Chat`](../../lib/slap/chat.ex) context module, which provides:

- Room management functions
- Message creation and retrieval
- User membership handling
- Search functionality
- Reaction management

### Schema Modules

The chat room data structures are defined in:

- [`Slap.Chat.Room`](../../lib/slap/chat/room.ex) - Room schema
- [`Slap.Chat.Message`](../../lib/slap/chat/message.ex) - Message schema
- [`Slap.Chat.RoomMembership`](../../lib/slap/chat/room_membership.ex) - Membership tracking
- [`Slap.Chat.Reply`](../../lib/slap/chat/reply.ex) - Thread replies
- [`Slap.Chat.Reaction`](../../lib/slap/chat/reaction.ex) - Message reactions
- [`Slap.Chat.MessageAttachment`](../../lib/slap/chat/message_attachment.ex) - File attachments

### LiveView Components

The chat room UI is implemented with:

- [`SlapWeb.ChatRoomLive`](../../lib/slap_web/live/chat_room_live.ex) - Main chat interface
- [`SlapWeb.ChatRoomLive.Index`](../../lib/slap_web/live/chat_room_live/index.ex) - Room listing
- [`SlapWeb.ChatRoomLive.Edit`](../../lib/slap_web/live/chat_room_live/edit.ex) - Room editing
- Various sub-components for specific UI elements

## Room Management

### Creating Rooms

Users can create new chat rooms with:

- **Name**: Required, unique identifier
- **Topic**: Optional description of the room's purpose

```elixir
def create_room(attrs) do
  %Room{}
  |> Room.changeset(attrs)
  |> Repo.insert()
end
```

### Editing Rooms

Room creators can edit room details:

```elixir
def update_room(%Room{} = room, attrs) do
  room
  |> Room.changeset(attrs)
  |> Repo.update()
end
```

### Deleting Rooms

Room creators can delete rooms, which also:

- Deletes all messages in the room
- Removes all memberships
- Cleans up associated data

### Room Membership

Users can join and leave rooms:

```elixir
def toggle_room_membership(room, user) do
  case get_room_membership(room, user) do
    nil -> join_room(room, user)
    membership -> leave_room(membership)
  end
end
```

## Real-time Messaging

### Message Flow

1. User submits message through the message form
2. Message is validated and saved to the database
3. Message is broadcast to all room subscribers
4. All connected users receive the message in real-time
5. Message appears in the chat interface

### Message Creation

```elixir
def create_message(room, attrs, user) do
  %Message{}
  |> Message.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:room, room)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> broadcast_message(room)
end
```

### Message Broadcasting

Messages are broadcast using Phoenix PubSub:

```elixir
defp broadcast_message({:ok, message}, room) do
  Phoenix.PubSub.broadcast(
    Slap.PubSub,
    "chat_room:#{room.id}",
    {:new_message, message}
  )
  {:ok, message}
end
```

### Message Pagination

Messages are loaded with pagination to handle large chat histories:

```elixir
def list_messages_in_room(%Room{id: room_id}, opts \\ []) do
  Message
  |> where([m], m.room_id == ^room_id)
  |> order_by([m], desc: m.inserted_at, desc: m.id)
  |> paginate(opts)
  |> Repo.all()
end
```

## Message Features

### Message Reactions

Users can react to messages with emojis:

```elixir
def add_reaction(emoji, %Message{} = message, %User{} = user) do
  %Reaction{}
  |> Reaction.changeset(%{emoji: emoji})
  |> Ecto.Changeset.put_assoc(:message, message)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> broadcast_reaction(message)
end
```

### Message Threads

Users can reply to messages to create threads:

```elixir
def create_reply(%Message{} = message, attrs, user) do
  %Reply{}
  |> Reply.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:message, message)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> broadcast_reply(message)
end
```

### Message Deletion

Users can delete their own messages:

```elixir
def delete_message_by_id(id, %User{id: user_id}) do
  Message
  |> where([m], m.id == ^id and m.user_id == ^user_id)
  |> Repo.one()
  |> case do
    nil -> {:error, :not_found}
    message -> delete_message(message)
  end
end
```

## File Uploads

### Supported Files

- PDF files (up to 10MB)
- Multiple files per message
- Secure storage in `priv/static/uploads/`

### Upload Process

1. User selects files in the message form
2. Files are validated for type and size
3. Files are copied to secure storage
4. Attachment records are created
5. Files are linked to the message

### Upload Implementation

```elixir
def create_message_attachment(message, upload) do
  case Slap.Uploads.upload_file(upload) do
    {:ok, file_path} ->
      %MessageAttachment{}
      |> MessageAttachment.changeset(%{
        filename: upload.filename,
        path: file_path,
        content_type: upload.content_type,
        size: upload.path |> File.stat!() |> Map.get(:size)
      })
      |> Ecto.Changeset.put_assoc(:message, message)
      |> Repo.insert()
    
    {:error, reason} ->
      {:error, reason}
  end
end
```

## Search Functionality

### Full-Text Search

Messages are searchable using PostgreSQL's full-text search:

```elixir
def search_messages(room_id, query, opts \\ []) do
  Message
  |> join(:inner, [m], u in assoc(m, :user))
  |> where([m, u], m.room_id == ^room_id)
  |> where([m, u], 
    fragment("to_tsvector('english', ?) @@ to_tsquery('english', ?)", m.body, ^query))
  |> order_by([m, u], 
    [desc: ts_rank(fragment("to_tsvector('english', ?)", m.body), 
                   fragment("to_tsquery('english', ?)", ^query))])
  |> paginate(opts)
  |> select([m, u], %{m | user: u})
  |> Repo.all()
end
```

### Search Features

- Whole word matching
- Case-insensitive search
- Multiple term support with AND logic
- Result ranking by relevance
- Real-time search result broadcasting

## Unread Message Tracking

### Read Status

The system tracks which messages each user has read:

```elixir
def update_last_read_id(room, user) do
  case get_room_membership(room, user) do
    nil -> {:error, :not_member}
    membership -> 
      membership
      |> RoomMembership.changeset(%{last_read_id: get_last_message_id(room)})
      |> Repo.update()
  end
end
```

### Unread Count

Unread message counts are calculated and displayed:

```elixir
def unread_message_count(%Room{} = room, %User{} = user) do
  case get_last_read_id(room, user) do
    nil -> get_total_message_count(room)
    last_read_id -> get_message_count_since(room, last_read_id)
  end
end
```

## LiveView Components

### ChatRoomLive

The main chat interface handles:

- Real-time message updates
- Message submission and validation
- Room navigation
- User presence
- Search functionality
- Voice call notifications

### MessageListComponent

Displays messages with:

- Date dividers for message organization
- Pagination for large message histories
- Unread message markers
- Message components with reactions and attachments

### MessageFormComponent

Handles message composition:

- Text input with auto-resize
- File attachment handling
- Form validation
- Submission handling

### SidebarComponent

Displays:

- Room list with unread counts
- User presence indicators
- Room navigation
- Direct messaging access

## Real-time Features

### Presence Tracking

Users' online/offline status is tracked:

```elixir
def track_user_presence(%{assigns: %{current_user: user}} = socket) do
  Phoenix.PubSub.subscribe(Slap.PubSub, "presence:#{user.id}")
  
  presence = %{
    user_at: user.id,
    online_at: :os.system_time(:millisecond)
  }
  
  SlapWeb.Presence.track(self(), "presence:#{user.id}", user.id, presence)
  {:ok, socket}
end
```

### PubSub Topics

The system uses several PubSub topics:

- `"chat_room:#{room_id}"` - Room-specific messages
- `"presence:#{user_id}"` - User presence
- `"search:#{room_id}"` - Search results

## User Interface

### Message Display

Messages are displayed with:

- User avatar and username
- Timestamp with relative time
- Message body with formatting
- Reactions with emoji counts
- Attachments with download links
- Reply thread indicators

### Message Composition

The message form includes:

- Auto-resizing text area
- File upload button
- Character counter
- Submit button
- Formatting options (future feature)

### Room Navigation

The sidebar provides:

- List of joined rooms
- Unread message counts
- Room creation button
- Search functionality
- User status indicators

## Performance Optimizations

### Database Indexes

Strategic indexes optimize common queries:

```sql
-- Message queries
CREATE INDEX messages_room_id_index ON messages(room_id);
CREATE INDEX messages_user_id_index ON messages(user_id);
CREATE INDEX messages_inserted_at_index ON messages(inserted_at);

-- Search optimization
CREATE INDEX messages_search_index ON messages USING gin(to_tsvector('english', body));
```

### Pagination

Cursor-based pagination handles large datasets:

```elixir
def paginate(query, %{after: cursor, limit: limit}) do
  query
  |> where([m], m.inserted_at < ^cursor or (m.inserted_at == ^cursor and m.id < ^cursor_id))
  |> limit(^limit)
end
```

### Caching

Frequently accessed data is cached:

- User information
- Room membership lists
- Unread message counts

## Security Considerations

### Authorization

Users can only:

- View messages in rooms they're members of
- Delete their own messages
- Edit rooms they created
- Join public rooms

### Input Validation

All user input is validated:

- Message length limits
- File type and size validation
- HTML sanitization (future feature)
- SQL injection prevention via Ecto

## Testing

### Test Coverage

Chat room tests include:

- Room creation and management
- Message creation and broadcasting
- User membership handling
- Search functionality
- File upload handling
- Real-time updates

### Test Fixtures

Test data is created using fixtures:

```elixir
def room_fixture(attrs \\ %{}) do
  {:ok, room} =
    attrs
    |> Enum.into(%{name: "Test Room", topic: "Test Topic"})
    |> Slap.Chat.create_room()
  
  room
end
```

This chat room system provides a robust foundation for real-time communication with features that enhance user experience and engagement.