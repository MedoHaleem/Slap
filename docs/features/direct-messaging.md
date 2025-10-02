# Direct Messaging System

This document provides a comprehensive overview of the direct messaging functionality in Slap, including private conversations, group conversations, and real-time messaging features.

## Overview

The direct messaging system allows users to:

- Create one-on-one private conversations
- Create and manage group conversations
- Send and receive real-time direct messages
- React to direct messages with emojis
- Share files in direct messages
- Search within direct message conversations
- Manage conversation participants and permissions

## Architecture

### Context Module

The direct messaging logic is centralized in the [`Slap.DirectMessaging`](../../lib/slap/direct_messaging.ex) context module, which provides:

- Conversation creation and management
- Direct message creation and retrieval
- Participant management
- Unread message tracking
- Search functionality
- Permission management

### Schema Modules

The direct messaging data structures are defined in:

- [`Slap.Chat.Conversation`](../../lib/slap/chat/conversation.ex) - Conversation schema
- [`Slap.Chat.DirectMessage`](../../lib/slap/chat/direct_message.ex) - Direct message schema
- [`Slap.Chat.ConversationParticipant`](../../lib/slap/chat/conversation_participant.ex) - Participant tracking
- [`Slap.Chat.ConversationInvite`](../../lib/slap/chat/conversation_invite.ex) - Invitation system
- [`Slap.Chat.ConversationSetting`](../../lib/slap/chat/conversation_setting.ex) - Conversation settings

### LiveView Components

The direct messaging UI is implemented with:

- [`SlapWeb.DirectMessagingComponent`](../../lib/slap_web/live/direct_messaging_component.ex) - Main DM interface
- Integration with [`SlapWeb.ChatRoomLive`](../../lib/slap_web/live/chat_room_live.ex) for unified messaging

## Conversation Types

### One-on-One Conversations

Private conversations between two users:

- Automatically created when users start messaging
- Unique per user pair
- No additional participants allowed
- Simple permission model

### Group Conversations

Multi-user conversations with advanced features:

- Multiple participants (2+ users)
- Roles and permissions
- Invitation system
- Conversation settings
- Participant management

## Conversation Management

### Creating Conversations

#### One-on-One Conversations

```elixir
def create_direct_message_conversation(attrs \\ %{}, user1, user2) do
  # Check if conversation already exists
  case get_conversation_between_users(user1.id, user2.id) do
    nil ->
      create_conversation_with_participants(attrs, [user1.id, user2.id])
    conversation ->
      {:ok, conversation}
  end
end
```

#### Group Conversations

```elixir
def create_group_conversation(attrs \\ %{}, participants, creator) do
  attrs
  |> Map.put(:participant_count, length(participants) + 1)
  |> create_conversation_with_participants([creator.id | participants])
end
```

### Conversation Settings

Group conversations have configurable settings:

```elixir
def create_conversation_settings(conversation) do
  %ConversationSetting{}
  |> ConversationSetting.changeset(%{
    conversation_id: conversation.id,
    is_public: false,
    allow_invites: true
  })
  |> Repo.insert()
end
```

## Participant Management

### Adding Participants

```elixir
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
```

### Removing Participants

```elixir
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

### Participant Roles

Participants can have different roles:

- **admin**: Full control over conversation
- **moderator**: Can manage participants and messages
- **member**: Standard participant permissions

```elixir
def promote_participant(%Conversation{id: conversation_id}, target_user_id, new_role, current_user) do
  with true <- user_has_permission?(conversation_id, current_user.id, :manage_participants),
       participant when not is_nil(participant) <- get_conversation_participant(conversation_id, target_user_id) do
    participant
    |> ConversationParticipant.changeset(%{role: new_role})
    |> Repo.update()
  else
    false -> {:error, :unauthorized}
    nil -> {:error, :not_found}
  end
end
```

## Direct Messaging

### Message Creation

```elixir
def send_direct_message(%Conversation{} = conversation, attrs, %User{} = user) do
  %DirectMessage{}
  |> DirectMessage.changeset(attrs)
  |> Ecto.Changeset.put_assoc(:conversation, conversation)
  |> Ecto.Changeset.put_assoc(:user, user)
  |> Repo.insert()
  |> update_conversation_timestamp(conversation)
  |> broadcast_direct_message(conversation)
end
```

### Message Broadcasting

Messages are broadcast using Phoenix PubSub:

```elixir
defp broadcast_direct_message({:ok, message}, conversation) do
  Phoenix.PubSub.broadcast(
    Slap.PubSub,
    "conversation:#{conversation.id}",
    {:new_direct_message, message}
  )
  
  # Notify all participants
  conversation
  |> list_conversation_participants()
  |> Enum.each(fn participant ->
    Phoenix.PubSub.broadcast(
      Slap.PubSub,
      "direct_messages:#{participant.user_id}",
      {:new_direct_message, message}
    )
  end)
  
  {:ok, message}
end
```

### Message Pagination

Messages are loaded with pagination for performance:

```elixir
def list_direct_messages(conversation_id, opts) when is_integer(conversation_id) do
  DirectMessage
  |> where([dm], dm.conversation_id == ^conversation_id)
  |> order_by([dm], desc: dm.inserted_at, desc: dm.id)
  |> maybe_preload([:user, :reactions, :attachments])
  |> paginate(opts)
  |> Repo.all()
end
```

## Invitation System

### Creating Invitations

```elixir
def create_conversation_invite(%Conversation{id: conversation_id}, invitee_id, inviter) do
  %ConversationInvite{}
  |> ConversationInvite.changeset(%{
    conversation_id: conversation_id,
    inviter_id: inviter.id,
    invitee_id: invitee_id,
    token: generate_invite_token(),
    status: "pending"
  })
  |> Repo.insert()
end
```

### Accepting Invitations

```elixir
def accept_conversation_invite(token, user) do
  with invite when not is_nil(invite) <- get_conversation_invite_by_token(token),
       true <- invite.invitee_id == user.id,
       true <- invite.status == "pending" do
    Repo.transaction(fn ->
      # Add user to conversation
      add_participant_to_conversation(invite.conversation, user.id)
      
      # Update invite status
      invite
      |> ConversationInvite.changeset(%{status: "accepted"})
      |> Repo.update()
    end)
  else
    nil -> {:error, :not_found}
    false -> {:error, :invalid}
  end
end
```

## Unread Message Tracking

### Marking as Read

```elixir
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
```

### Unread Count Calculation

```elixir
def count_unread_messages(conversation_id, user_id) do
  case get_conversation_participant(conversation_id, user_id) do
    nil -> 0
    participant ->
      DirectMessage
      |> where([dm], dm.conversation_id == ^conversation_id)
      |> where([dm], dm.inserted_at > ^participant.last_read_at)
      |> Repo.aggregate(:count, :id)
  end
end
```

### User Conversations with Unread Counts

```elixir
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

## Search Functionality

### Searching Direct Messages

```elixir
def search_direct_messages(conversation_id, query, opts \\ []) do
  DirectMessage
  |> join(:inner, [dm], u in assoc(dm, :user))
  |> where([dm, u], dm.conversation_id == ^conversation_id)
  |> where([dm, u], 
    fragment("to_tsvector('english', ?) @@ to_tsquery('english', ?)", dm.body, ^query))
  |> order_by([dm, u], 
    [desc: ts_rank(fragment("to_tsvector('english', ?)", dm.body), 
                   fragment("to_tsquery('english', ?)", ^query))])
  |> paginate(opts)
  |> select([dm, u], %{dm | user: u})
  |> Repo.all()
end
```

## LiveView Component

### DirectMessagingComponent

The main direct messaging interface handles:

- Conversation list with unread counts
- Message display and pagination
- Message composition and sending
- Participant management
- Group conversation creation
- Invitation handling
- Real-time updates

### Component State

```elixir
def update(assigns, socket) do
  socket =
    socket
    |> assign(:current_user, assigns.current_user)
    |> assign(:conversations, get_user_conversations(assigns.current_user))
    |> assign(:selected_conversation, nil)
    |> assign(:messages, [])
    |> assign(:form, to_form(%{"body" => ""}))
    |> assign(:show_group_form, false)
    |> assign(:show_invite_form, false)
  
  {:ok, socket}
end
```

### Event Handling

```elixir
def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
  case socket.assigns.selected_conversation do
    nil ->
      {:noreply, put_flash(socket, :error, "Select a conversation first")}
    conversation ->
      case send_direct_message(conversation, %{body: body}, socket.assigns.current_user) do
        {:ok, _message} ->
          {:noreply, assign(socket, :form, to_form(%{"body" => ""}))}
        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(%{"body" => body}, errors: changeset.errors))}
      end
  end
end
```

### Real-time Updates

```elixir
def handle_info({:new_direct_message, message}, socket) do
  socket =
    socket
    |> update_conversation_list()
    |> maybe_add_message_to_conversation(message)
  
  {:noreply, socket}
end
```

## Performance Optimizations

### Database Indexes

Strategic indexes optimize direct messaging queries:

```sql
-- Conversation queries
CREATE INDEX idx_conversation_participants_user_id ON conversation_participants(user_id);
CREATE INDEX idx_conversation_participants_conversation_id ON conversation_participants(conversation_id);

-- Message queries
CREATE INDEX idx_direct_messages_conversation_id ON direct_messages(conversation_id);
CREATE INDEX idx_direct_messages_conversation_id_inserted_at ON direct_messages(conversation_id, inserted_at);

-- Search optimization
CREATE INDEX idx_direct_messages_search ON direct_messages USING gin(to_tsvector('english', body));

-- Performance indexes
CREATE INDEX idx_conversations_last_message_at ON conversations(last_message_at DESC NULLS LAST);
```

### Efficient Queries

Optimized queries for common operations:

```elixir
# Get conversation between two users
def get_conversation_between_users(user1_id, user2_id) do
  from(c in Conversation,
    join: cp1 in ConversationParticipant, on: c.id == cp1.conversation_id,
    join: cp2 in ConversationParticipant, on: c.id == cp2.conversation_id,
    where: cp1.user_id == ^user1_id and cp2.user_id == ^user2_id,
    where: c.participant_count == 2
  )
  |> Repo.one()
end
```

## Security Considerations

### Authorization

Users can only:

- View conversations they participate in
- Send messages to conversations they're in
- Manage participants if they have permission
- Invite users if conversation allows it

### Permission Checking

```elixir
def user_has_permission?(conversation_id, user_id, permission) do
  case get_conversation_participant(conversation_id, user_id) do
    nil -> false
    participant ->
      case permission do
        :read_messages -> true
        :send_messages -> participant.role in ["member", "moderator", "admin"]
        :manage_participants -> participant.role in ["moderator", "admin"]
        :edit_settings -> participant.role == "admin"
      end
  end
end
```

### Rate Limiting

Message sending is rate limited to prevent spam:

```elixir
def send_direct_message_with_rate_limit(conversation, attrs, user) do
  case check_rate_limit(user.id, :send_direct_message) do
    :ok -> send_direct_message(conversation, attrs, user)
    {:error, :rate_limited} -> {:error, :rate_limited}
  end
end
```

## Testing

### Test Coverage

Direct messaging tests include:

- Conversation creation and management
- Message creation and broadcasting
- Participant management
- Permission checking
- Invitation system
- Unread message tracking
- Search functionality

### Test Fixtures

Test data is created using fixtures:

```elixir
def conversation_fixture(attrs \\ %{}) do
  user = user_fixture()
  other_user = user_fixture()
  
  {:ok, conversation} = 
    attrs
    |> Enum.into(%{title: "Test Conversation"})
    |> DirectMessaging.create_direct_message_conversation(user, other_user)
  
  conversation
end
```

## Integration with Chat Rooms

The direct messaging system integrates with the main chat interface:

- Unified sidebar showing both rooms and conversations
- Consistent message display and interaction
- Shared components for reactions and attachments
- Integrated search across rooms and conversations

This direct messaging system provides a comprehensive private communication solution with features that support both simple one-on-one conversations and complex group discussions.