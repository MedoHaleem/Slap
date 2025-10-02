# Test Fixtures

This document provides a comprehensive overview of the test fixtures used in the Slap application to generate consistent test data.

## Overview

Fixtures are functions that create test data with default values, making tests more readable and maintainable. They provide:

- Consistent test data across tests
- Default values with easy customization
- Relationships between entities
- Reusable data generation patterns

## Fixture Structure

### Directory Organization

```
test/support/fixtures/
├── accounts_fixtures.ex          # User and authentication fixtures
├── chat_fixtures.ex              # Chat room and message fixtures
├── direct_messaging_fixtures.ex  # Direct messaging fixtures
└── group_conversation_fixtures.ex # Group conversation fixtures
```

## Accounts Fixtures

**Location**: [`test/support/fixtures/accounts_fixtures.ex`](../../test/support/fixtures/accounts_fixtures.ex)

Provides fixtures for user accounts and authentication.

### User Fixture

```elixir
defmodule Slap.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating entities
  via the `Slap.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "ValidPassword123!"

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: unique_user_email(),
        password: valid_user_password()
      })
      |> Slap.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token, _] = String.split(captured.body, "[TOKEN]")
    token
  end
end
```

### Usage Examples

```elixir
# Create a user with default values
user = user_fixture()

# Create a user with custom attributes
user = user_fixture(%{
  username: "customuser",
  email: "custom@example.com"
})

# Extract user token from email
token = extract_user_token(fn email ->
  Accounts.deliver_user_confirmation_instructions(user, &"http://localhost:4000#{&1}")
end)
```

## Chat Fixtures

**Location**: [`test/support/fixtures/chat_fixtures.ex`](../../test/support/fixtures/chat_fixtures.ex)

Provides fixtures for chat rooms, messages, and related entities.

### Room Fixture

```elixir
defmodule Slap.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating entities
  via the `Slap.Chat` context.
  """

  def unique_room_name, do: "room#{System.unique_integer()}"

  def room_fixture(attrs \\ %{}) do
    {:ok, room} =
      attrs
      |> Enum.into(%{
        name: unique_room_name(),
        topic: "Test topic"
      })
      |> Slap.Chat.create_room()

    room
  end

  def message_fixture(room \\ nil, user \\ nil, attrs \\ %{}) do
    room = room || room_fixture()
    user = user || user_fixture()

    {:ok, message} =
      attrs
      |> Enum.into(%{
        body: "Test message"
      })
      |> Slap.Chat.create_message(room, user)

    message
  end

  def room_membership_fixture(room \\ nil, user \\ nil, attrs \\ %{}) do
    room = room || room_fixture()
    user = user || user_fixture()

    {:ok, membership} =
      attrs
      |> Enum.into(%{})
      |> Slap.Chat.toggle_room_membership(room, user)

    membership
  end

  def reaction_fixture(message \\ nil, user \\ nil, attrs \\ %{}) do
    message = message || message_fixture()
    user = user || user_fixture()

    {:ok, reaction} =
      attrs
      |> Enum.into(%{
        emoji: "👍"
      })
      |> Slap.Chat.add_reaction("👍", message, user)

    reaction
  end

  def reply_fixture(message \\ nil, user \\ nil, attrs \\ %{}) do
    message = message || message_fixture()
    user = user || user_fixture()

    {:ok, reply} =
      attrs
      |> Enum.into(%{
        body: "Test reply"
      })
      |> Slap.Chat.create_reply(message, user)

    reply
  end
end
```

### Usage Examples

```elixir
# Create a room with default values
room = room_fixture()

# Create a room with custom attributes
room = room_fixture(%{
  name: "Custom Room",
  topic: "Custom topic"
})

# Create a message in a room
message = message_fixture(room, user)

# Create a message with custom body
message = message_fixture(room, user, %{body: "Custom message"})

# Add a reaction to a message
reaction = reaction_fixture(message, user, %{emoji: "❤️"})

# Create a reply to a message
reply = reply_fixture(message, user, %{body: "Custom reply"})
```

## Direct Messaging Fixtures

**Location**: [`test/support/fixtures/direct_messaging_fixtures.ex`](../../test/support/fixtures/direct_messaging_fixtures.ex)

Provides fixtures for direct messages and conversations.

### Conversation and Message Fixtures

```elixir
defmodule Slap.DirectMessagingFixtures do
  @moduledoc """
  This module defines test helpers for creating entities
  via the `Slap.DirectMessaging` context.
  """

  def conversation_fixture(attrs \\ %{}) do
    user1 = user_fixture()
    user2 = user_fixture()

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        title: "Test Conversation"
      })
      |> Slap.DirectMessaging.create_direct_message_conversation(user1, user2)

    conversation
  end

  def direct_message_fixture(conversation \\ nil, user \\ nil, attrs \\ %{}) do
    conversation = conversation || conversation_fixture()
    user = user || user_fixture()

    {:ok, message} =
      attrs
      |> Enum.into(%{
        body: "Test direct message"
      })
      |> Slap.DirectMessaging.send_direct_message(conversation, attrs, user)

    message
  end

  def conversation_participant_fixture(conversation \\ nil, user \\ nil, attrs \\ %{}) do
    conversation = conversation || conversation_fixture()
    user = user_fixture()

    {:ok, participant} =
      attrs
      |> Enum.into(%{
        role: "member"
      })
      |> Slap.DirectMessaging.add_participant_to_conversation(conversation, user.id)

    participant
  end

  def conversation_invite_fixture(conversation \\ nil, inviter \\ nil, invitee \\ nil, attrs \\ %{}) do
    conversation = conversation || conversation_fixture()
    inviter = inviter || user_fixture()
    invitee = invitee || user_fixture()

    {:ok, invite} =
      attrs
      |> Enum.into(%{})
      |> Slap.DirectMessaging.create_conversation_invite(conversation, invitee.id, inviter)

    invite
  end
end
```

### Usage Examples

```elixir
# Create a direct message conversation
conversation = conversation_fixture()

# Create a conversation with custom title
conversation = conversation_fixture(%{title: "Custom Conversation"})

# Send a direct message
message = direct_message_fixture(conversation, user)

# Send a message with custom body
message = direct_message_fixture(conversation, user, %{body: "Custom message"})

# Add a participant to conversation
participant = conversation_participant_fixture(conversation, user, %{role: "admin"})

# Create a conversation invite
invite = conversation_invite_fixture(conversation, inviter, invitee)
```

## Group Conversation Fixtures

**Location**: [`test/support/fixtures/group_conversation_fixtures.ex`](../../test/support/fixtures/group_conversation_fixtures.ex)

Provides fixtures for group conversations with multiple participants.

### Group Conversation Fixtures

```elixir
defmodule Slap.GroupConversationFixtures do
  @moduledoc """
  This module defines test helpers for creating group conversation entities
  via the `Slap.DirectMessaging` context.
  """

  def group_conversation_fixture(attrs \\ %{}) do
    creator = user_fixture()
    participants = [user_fixture(), user_fixture()]

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        title: "Test Group Conversation"
      })
      |> Slap.DirectMessaging.create_group_conversation(participants, creator)

    conversation
  end

  def group_conversation_with_participants_fixture(participant_count \\ 3, attrs \\ %{}) do
    creator = user_fixture()
    participants = for _i <- 1..participant_count, do: user_fixture()

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        title: "Group with #{participant_count} participants"
      })
      |> Slap.DirectMessaging.create_group_conversation(participants, creator)

    conversation
  end

  def public_group_conversation_fixture(attrs \\ %{}) do
    creator = user_fixture()
    participants = [user_fixture(), user_fixture()]

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        title: "Public Group Conversation",
        is_public: true
      })
      |> Slap.DirectMessaging.create_group_conversation(participants, creator)

    # Set conversation as public
    {:ok, _settings} = Slap.DirectMessaging.update_conversation_settings(conversation, %{
      is_public: true,
      allow_invites: true
    }, creator)

    conversation
  end
end
```

### Usage Examples

```elixir
# Create a group conversation
conversation = group_conversation_fixture()

# Create a group with custom title
conversation = group_conversation_fixture(%{title: "Custom Group"})

# Create a group with specific number of participants
conversation = group_conversation_with_participants_fixture(5)

# Create a public group conversation
conversation = public_group_conversation_fixture()
```

## Custom Fixture Functions

### Complex Scenario Fixtures

```elixir
defmodule Slap.ScenarioFixtures do
  @moduledoc """
  This module defines test helpers for creating complex scenarios.
  """

  def chat_room_with_messages_fixture(message_count \\ 5) do
    user = user_fixture()
    room = room_fixture()
    
    # Join user to room
    Slap.Chat.toggle_room_membership(room, user)
    
    # Create messages
    messages = 
      for i <- 1..message_count do
        message_fixture(room, user, %{body: "Message #{i}"})
      end
    
    %{room: room, user: user, messages: messages}
  end

  def conversation_with_messages_fixture(message_count \\ 5) do
    user1 = user_fixture()
    user2 = user_fixture()
    
    {:ok, conversation} = Slap.DirectMessaging.create_direct_message_conversation(user1, user2)
    
    # Create messages alternating between users
    messages = 
      for i <- 1..message_count do
        sender = if rem(i, 2) == 0, do: user1, else: user2
        direct_message_fixture(conversation, sender, %{body: "Message #{i}"})
      end
    
    %{conversation: conversation, user1: user1, user2: user2, messages: messages}
  end

  def active_chat_scenario_fixture do
    # Create multiple users
    users = for _i <- 1..3, do: user_fixture()
    
    # Create rooms
    rooms = for _i <- 1..2, do: room_fixture()
    
    # Join users to rooms
    for room <- rooms, user <- users do
      Slap.Chat.toggle_room_membership(room, user)
    end
    
    # Create messages in rooms
    room_messages = 
      for room <- rooms do
        for user <- users do
          message_fixture(room, user, %{body: "#{user.username} in #{room.name}"})
        end
      end
    
    # Create direct message conversations
    conversations = 
      for {user1, i} <- Enum.with_index(users),
          {user2, j} <- Enum.with_index(users),
          i < j do
        {:ok, conversation} = Slap.DirectMessaging.create_direct_message_conversation(user1, user2)
        
        # Add some messages
        for _k <- 1..3 do
          direct_message_fixture(conversation, user1, %{body: "From #{user1.username}"})
          direct_message_fixture(conversation, user2, %{body: "From #{user2.username}"})
        end
        
        conversation
      end
    
    %{
      users: users,
      rooms: rooms,
      room_messages: List.flatten(room_messages),
      conversations: conversations
    }
  end
end
```

## Fixture Best Practices

### Naming Conventions

- Use descriptive names that clearly indicate what's being created
- Include the entity type in the function name (user_fixture, room_fixture)
- Use consistent naming patterns across all fixtures

### Default Values

- Provide sensible defaults that work for most tests
- Make defaults realistic but generic
- Override defaults when specific values are needed

### Relationships

- Handle relationships between entities automatically
- Create dependent entities when needed
- Allow customization of related entities

### Uniqueness

- Ensure generated values are unique across test runs
- Use System.unique_integer() or similar for uniqueness
- Include timestamps or random strings when needed

### Cleanup

- Let database transactions handle cleanup automatically
- Don't manually delete data in fixtures
- Use sandbox mode for test isolation

## Using Fixtures in Tests

### Test Setup

```elixir
defmodule SlapWeb.ChatRoomLiveTest do
  use SlapWeb.ConnCase
  import Phoenix.LiveViewTest
  import Slap.ChatFixtures

  setup [:register_and_log_in_user]

  test "displays messages", %{conn: conn, user: user} do
    room = room_fixture()
    message = message_fixture(room, user)
    
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
    
    assert render(view) =~ message.body
  end
end
```

### Custom Test Helpers

```elixir
defmodule Slap.TestHelpers do
  @moduledoc """
  Custom test helpers for common scenarios.
  """

  def setup_chat_room_with_messages(%{conn: conn, user: user}) do
    room = room_fixture()
    message = message_fixture(room, user)
    
    %{conn: conn, user: user, room: room, message: message}
  end

  def setup_direct_message_conversation(%{conn: conn, user: user}) do
    other_user = user_fixture()
    {:ok, conversation} = DirectMessaging.create_direct_message_conversation(user, other_user)
    
    %{conn: conn, user: user, other_user: other_user, conversation: conversation}
  end
end
```

## Performance Considerations

### Lazy Loading

Create fixtures only when needed:

```elixir
def test_with_lazy_fixture do
  # Don't create fixture at the top
  # Create it only when needed
  {:ok, result} = do_something()
  
  if result.requires_fixture? do
    room = room_fixture()
    # Use room
  end
end
```

### Shared Fixtures

Reuse expensive fixtures across multiple tests:

```elixir
defmodule Slap.SharedFixtures do
  use ExUnit.CaseTemplate
  
  using do
    quote do
      import Slap.SharedFixtures
    end
  end
  
  setup_all do
    # Create shared fixtures once per test suite
    {:ok, shared_data: create_shared_data()}
  end
end
```

This fixtures documentation provides a comprehensive overview of the test data generation patterns used in the Slap application, making tests more readable, maintainable, and consistent.