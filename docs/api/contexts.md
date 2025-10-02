# Context Modules

This document provides a comprehensive overview of the context modules in the Slap application, which contain the business logic and data operations.

## Overview

Context modules in Phoenix provide a boundary between the web layer and the data layer. They encapsulate business logic, data operations, and provide a clean API for the rest of the application to interact with.

## Core Context Modules

### Slap.Accounts

**Location**: [`lib/slap/accounts.ex`](../../lib/slap/accounts.ex)

Handles user authentication, registration, and profile management.

#### Key Functions

##### User Registration

```elixir
@doc """
Registers a user.

## Parameters

- `attrs`: Map of user attributes (email, username, password)

## Returns

- `{:ok, user}` on success
- `{:error, changeset}` on failure

## Examples

    iex> register_user(%{email: "test@example.com", username: "test", password: "password"})
    {:ok, %User{}}

"""
def register_user(attrs) do
  %User{}
  |> User.registration_changeset(attrs)
  |> Repo.insert()
end
```

##### User Authentication

```elixir
@doc """
Authenticates a user by email or username and password.

## Parameters

- `email_or_username`: User's email or username
- `password`: User's password

## Returns

- `{:ok, user}` on success
- `{:error, :unauthorized}` on failure

"""
def get_authenticated_user(email_or_username, password) do
  user = Repo.get_by(User, [email: email_or_username]) || 
         Repo.get_by(User, [username: email_or_username])
  
  if user && User.valid_password?(user, password) do
    {:ok, user}
  else
    {:error, :unauthorized}
  end
end
```

##### User Management

```elixir
@doc """
Updates user settings.

## Parameters

- `user`: The user struct to update
- `attrs`: Map of attributes to update

## Returns

- `{:ok, user}` on success
- `{:error, changeset}` on failure

"""
def update_user(%User{} = user, attrs) do
  user
  |> User.settings_changeset(attrs)
  |> Repo.update()
end
```

##### Password Management

```elixir
@doc """
Updates user password.

## Parameters

- `user`: The user struct
- `password`: Current password for verification
- `attrs`: Map with new password

## Returns

- `{:ok, user}` on success
- `{:error, :invalid_password}` if current password is invalid
- `{:error, changeset}` on validation failure

"""
def update_user_password(user, password, attrs) do
  user
  |> User.password_changeset(attrs)
  |> User.validate_current_password(password)
  |> Repo.update()
end
```

##### Session Management

```elixir
@doc """
Generates a session token for a user.

## Parameters

- `user`: The user struct

## Returns

- Token string

"""
def generate_user_session_token(user) do
  {token, user_token} = UserToken.build_session_token(user)
  Repo.insert!(user_token)
  token
end

@doc """
Gets user by session token.

## Parameters

- `token`: Session token

## Returns

- User struct or nil

"""
def get_user_by_session_token(token) do
  {:ok, query} = UserToken.verify_session_token_query(token)
  Repo.one(query)
end
```

### Slap.Chat

**Location**: [`lib/slap/chat.ex`](../../lib/slap/chat.ex)

Handles chat room management, messages, and related functionality.

#### Key Functions

##### Room Management

```elixir
@doc """
Creates a new chat room.

## Parameters

- `attrs`: Map of room attributes (name, topic)

## Returns

- `{:ok, room}` on success
- `{:error, changeset}` on failure

"""
def create_room(attrs) do
  %Room{}
  |> Room.changeset(attrs)
  |> Repo.insert()
end

@doc """
Updates a chat room.

## Parameters

- `room`: The room struct to update
- `attrs`: Map of attributes to update

## Returns

- `{:ok, room}` on success
- `{:error, changeset}` on failure

"""
def update_room(%Room{} = room, attrs) do
  room
  |> Room.changeset(attrs)
  |> Repo.update()
end
```

##### Room Membership

```elixir
@doc """
Toggles room membership for a user.

## Parameters

- `room`: The room struct
- `user`: The user struct

## Returns

- `{:ok, membership}` on success
- `{:error, reason}` on failure

"""
def toggle_room_membership(room, user) do
  case get_room_membership(room, user) do
    nil -> join_room(room, user)
    membership -> leave_room(membership)
  end
end
```

##### Message Management

```elixir
@doc """
Creates a new message in a room.

## Parameters

- `room`: The room struct
- `attrs`: Map of message attributes (body)
- `user`: The user creating the message

## Returns

- `{:ok, message}` on success
- `{:error, changeset}` on failure

"""
def create_message(room, attrs, user) do
  %Message{}
  |> Message.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:room, room)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> broadcast_message(room)
end

@doc """
Lists messages in a room with pagination.

## Parameters

- `room`: The room struct
- `opts`: Options for pagination (page, per_page)

## Returns

- List of message structs

"""
def list_messages_in_room(%Room{id: room_id}, opts \\ []) do
  Message
  |> where([m], m.room_id == ^room_id)
  |> order_by([m], desc: m.inserted_at, desc: m.id)
  |> maybe_preload([:user, :reactions, :attachments])
  |> paginate(opts)
  |> Repo.all()
end
```

##### Message Search

```elixir
@doc """
Searches messages in a room.

## Parameters

- `room_id`: The room ID
- `query`: Search query string
- `opts`: Search options (page, per_page)

## Returns

- List of matching message structs

"""
def search_messages(room_id, query, opts \\ []) do
  search_query = build_search_query(query)
  
  Message
  |> join(:inner, [m], u in assoc(m, :user))
  |> where([m, u], m.room_id == ^room_id)
  |> where([m, u], 
    fragment("to_tsvector('english', ?) @@ to_tsquery('english', ?)", m.body, ^search_query))
  |> order_by([m, u], 
    [desc: ts_rank(fragment("to_tsvector('english', ?)", m.body), 
                   fragment("to_tsquery('english', ?)", ^search_query))])
  |> maybe_preload([:user, :reactions, :attachments])
  |> paginate(opts)
  |> Repo.all()
end
```

##### Reactions

```elixir
@doc """
Adds a reaction to a message.

## Parameters

- `emoji`: The emoji character
- `message`: The message struct
- `user`: The user adding the reaction

## Returns

- `{:ok, reaction}` on success
- `{:error, changeset}` on failure

"""
def add_reaction(emoji, %Message{} = message, %User{} = user) do
  %Reaction{}
  |> Reaction.changeset(%{emoji: emoji})
  |> Ecto.Changeset.put_assoc(:message, message)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> broadcast_reaction(message)
end

@doc """
Removes a reaction from a message.

## Parameters

- `emoji`: The emoji character
- `message`: The message struct
- `user`: The user removing the reaction

## Returns

- `{:ok, reaction}` on success
- `{:error, reason}` on failure

"""
def remove_reaction(emoji, %Message{} = message, %User{} = user) do
  Reaction
  |> where([r], r.message_id == ^message.id and r.user_id == ^user.id and r.emoji == ^emoji)
  |> Repo.one()
  |> case do
    nil -> {:error, :not_found}
    reaction -> 
      Repo.delete(reaction)
      |> broadcast_reaction_removed(message)
  end
end
```

### Slap.DirectMessaging

**Location**: [`lib/slap/direct_messaging.ex`](../../lib/slap/direct_messaging.ex)

Handles direct messaging functionality for one-on-one and group conversations.

#### Key Functions

##### Conversation Management

```elixir
@doc """
Creates a direct message conversation between two users.

## Parameters

- `attrs`: Map of conversation attributes
- `user1`: First user
- `user2`: Second user

## Returns

- `{:ok, conversation}` on success
- `{:error, changeset}` on failure

"""
def create_direct_message_conversation(attrs \\ %{}, user1, user2) do
  case get_conversation_between_users(user1.id, user2.id) do
    nil ->
      create_conversation_with_participants(attrs, [user1.id, user2.id])
    conversation ->
      {:ok, conversation}
  end
end

@doc """
Creates a group conversation.

## Parameters

- `attrs`: Map of conversation attributes
- `participants`: List of user IDs to add
- `creator`: The user creating the conversation

## Returns

- `{:ok, conversation}` on success
- `{:error, changeset}` on failure

"""
def create_group_conversation(attrs \\ %{}, participants, creator) do
  attrs
  |> Map.put(:participant_count, length(participants) + 1)
  |> create_conversation_with_participants([creator.id | participants])
end
```

##### Direct Messages

```elixir
@doc """
Sends a direct message in a conversation.

## Parameters

- `conversation`: The conversation struct
- `attrs`: Map of message attributes (body)
- `user`: The user sending the message

## Returns

- `{:ok, message}` on success
- `{:error, changeset}` on failure

"""
def send_direct_message(%Conversation{} = conversation, attrs, %User{} = user) do
  %DirectMessage{}
  |> DirectMessage.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:conversation, conversation)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> update_conversation_timestamp(conversation)
  |> broadcast_direct_message(conversation)
end

@doc """
Lists direct messages in a conversation.

## Parameters

- `conversation_id`: The conversation ID
- `opts`: Options for pagination (page, per_page)

## Returns

- List of direct message structs

"""
def list_direct_messages(conversation_id, opts) when is_integer(conversation_id) do
  DirectMessage
  |> where([dm], dm.conversation_id == ^conversation_id)
  |> order_by([dm], desc: dm.inserted_at, desc: dm.id)
  |> maybe_preload([:user, :reactions, :attachments])
  |> paginate(opts)
  |> Repo.all()
end
```

##### Participant Management

```elixir
@doc """
Adds a participant to a conversation.

## Parameters

- `conversation`: The conversation struct
- `user_id`: The user ID to add

## Returns

- `{:ok, participant}` on success
- `{:error, changeset}` on failure

"""
def add_participant_to_conversation(%Conversation{} = conversation, user_id) do
  %ConversationParticipant{}
  |> ConversationParticipant.changeset(%{
    conversation_id: conversation.id,
    user_id: user_id,
    role: "member"
  })
  |> Repo.insert()
  |> update_participant_count(conversation)
end

@doc """
Removes a participant from a conversation.

## Parameters

- `conversation`: The conversation struct
- `user_id`: The user ID to remove

## Returns

- `{:ok, participant}` on success
- `{:error, reason}` on failure

"""
def remove_participant_from_conversation(%Conversation{} = conversation, user_id) do
  ConversationParticipant
  |> where([cp], cp.conversation_id == ^conversation.id and cp.user_id == ^user_id)
  |> Repo.one()
  |> case do
    nil -> {:error, :not_found}
    participant -> 
      Repo.delete(participant)
      |> update_participant_count(conversation)
  end
end
```

##### Unread Message Tracking

```elixir
@doc """
Marks a conversation as read for a user.

## Parameters

- `conversation`: The conversation struct
- `user`: The user marking as read

## Returns

- `{:ok, participant}` on success
- `{:error, reason}` on failure

"""
def mark_conversation_read(%Conversation{} = conversation, %User{} = user) do
  case get_conversation_participant(conversation.id, user.id) do
    nil -> {:error, :not_participant}
    participant ->
      participant
      |> ConversationParticipant.changeset(%{last_read_at: DateTime.utc_now()})
      |> Repo.update()
      |> broadcast_read_status(conversation, user.id)
  end
end

@doc """
Gets user conversations with unread counts.

## Parameters

- `user`: The user struct

## Returns

- List of conversations with unread counts

"""
def get_user_conversations_with_unread_counts(%User{id: user_id}) do
  from(c in Conversation,
    join: cp in ConversationParticipant,
    on: c.id == cp.conversation_id and cp.user_id == ^user_id,
    left_join: dm in DirectMessage,
    on: c.id == dm.conversation_id and dm.inserted_at > cp.last_read_at,
    group_by: [c.id, cp.last_read_at],
    select: %{
      conversation: c,
      unread_count: count(dm.id),
      last_read_at: cp.last_read_at
    },
    order_by: [desc: c.last_message_at]
  )
  |> Repo.all()
end
```

### Slap.Uploads

**Location**: [`lib/slap/uploads.ex`](../../lib/slap/uploads.ex)

Handles file upload functionality including validation and storage.

#### Key Functions

```elixir
@doc """
Uploads a file to the storage system.

## Parameters

- `upload`: Plug.Upload struct with file information

## Returns

- `{:ok, path}` on success
- `{:error, reason}` on failure

"""
def upload_file(%Plug.Upload{path: temp_path, filename: filename}) do
  upload = %Plug.Upload{path: temp_path, filename: filename}
  
  with :ok <- validate_file_type(upload),
       :ok <- validate_file_size(upload),
       unique_filename <- generate_unique_filename(filename),
       upload_path <- get_upload_path(unique_filename, upload.content_type),
       :ok <- File.cp(temp_path, upload_path) do
    {:ok, "/uploads/" <> unique_filename}
  else
    {:error, reason} -> {:error, reason}
  end
end

@doc """
Deletes a file from storage.

## Parameters

- `file_path`: The relative path to the file

## Returns

- `:ok` on success
- `{:error, reason}` on failure

"""
def delete_file(file_path) do
  full_path = Path.join("priv/static", file_path)
  
  case File.rm(full_path) do
    :ok -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

## Context Design Patterns

### Error Handling

Contexts use consistent error handling patterns:

```elixir
def create_message(room, attrs, user) do
  %Message{}
  |> Message.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:room, room)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> case do
    {:ok, message} -> 
      broadcast_message(room, message)
      {:ok, message}
    
    {:error, changeset} -> 
      {:error, changeset}
  end
end
```

### Data Validation

Contexts rely on schema changesets for validation:

```elixir
def create_room(attrs) do
  %Room{}
  |> Room.changeset(attrs)
  |> Repo.insert()
end
```

### Broadcasting

Contexts broadcast events for real-time updates:

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

### Transaction Support

Contexts use transactions for multi-step operations:

```elixir
def create_conversation_with_participants(attrs, participant_ids) do
  Repo.transaction(fn ->
    with {:ok, conversation} <- create_conversation(attrs),
         participants <- create_participants(conversation, participant_ids) do
      conversation
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end
```

## Context Testing

### Unit Tests

```elixir
defmodule Slap.ChatTest do
  use Slap.DataCase
  
  describe "create_message/3" do
    test "creates message with valid attributes" do
      user = user_fixture()
      room = room_fixture()
      
      attrs = %{body: "Test message"}
      
      assert {:ok, %Message{}} = Chat.create_message(room, attrs, user)
    end
    
    test "returns error with invalid attributes" do
      user = user_fixture()
      room = room_fixture()
      
      attrs = %{body: ""}
      
      assert {:error, %Ecto.Changeset{}} = Chat.create_message(room, attrs, user)
    end
  end
end
```

### Integration Tests

```elixir
defmodule Slap.DirectMessagingTest do
  use Slap.DataCase
  
  describe "send_direct_message/3" do
    test "sends message and broadcasts update" do
      user1 = user_fixture()
      user2 = user_fixture()
      
      {:ok, conversation} = DirectMessaging.create_direct_message_conversation(user1, user2)
      
      # Subscribe to updates
      Phoenix.PubSub.subscribe(Slap.PubSub, "conversation:#{conversation.id}")
      
      attrs = %{body: "Test message"}
      
      assert {:ok, message} = DirectMessaging.send_direct_message(conversation, attrs, user1)
      
      # Verify broadcast
      assert_receive {:new_direct_message, ^message}
    end
  end
end
```

## Best Practices

### Function Design

- Use descriptive function names
- Include comprehensive @doc annotations
- Specify types with @spec
- Handle errors consistently
- Use pattern matching for clarity

### Data Operations

- Use changesets for validation
- Wrap multi-step operations in transactions
- Preload associations efficiently
- Optimize database queries

### Real-time Updates

- Broadcast events after successful operations
- Use descriptive event names
- Include relevant data in broadcasts
- Handle subscription errors

### Security

- Validate all inputs
- Check permissions before operations
- Use parameterized queries
- Sanitize outputs

This context module documentation provides a comprehensive overview of the business logic layer in the Slap application, making it easier for developers to understand and extend the functionality.