# DirectMessaging Context Refactoring Guide

This guide provides specific instructions for refactoring the DirectMessaging context to use the new shared modules.

## Overview

The DirectMessaging context (`lib/slap/direct_messaging.ex`) is over 1,100 lines and contains several areas that can be refactored using the shared modules:

1. Rate limiting logic (lines 845-876)
2. Constants and magic numbers
3. Permission checking logic
4. Pagination and search functionality
5. Error handling

## Step-by-Step Refactoring

### 1. Add Imports and Replace Constants

**Add these imports at the top of the file:**

```elixir
alias Slap.{Constants, Authorization, RateLimiter, ErrorHandler, Pagination, QueryBuilder, Messaging}
```

**Replace the constants section (lines 17-25):**

```elixir
# Remove these lines:
@default_message_limit 50
@rate_limit_window 60_000
@rate_limit_max_messages 30
@max_participants Conversation.max_participants()

# Replace with:
@default_message_limit Constants.default_message_limit()
@rate_limit_window Constants.rate_limit_window()
@rate_limit_max_messages Constants.rate_limit_max_messages()
@max_participants Constants.max_participants()
```

### 2. Replace Rate Limiting Logic

**Replace the `check_rate_limit` function (lines 845-876):**

```elixir
# Remove this entire function:
defp check_rate_limit(user_id, conversation_id) do
  # Old ETS-based implementation
end

# Replace with calls to RateLimiter in send_direct_message:
def send_direct_message(%Conversation{} = conversation, attrs, %User{} = user) do
  # Check rate limit before sending
  case RateLimiter.check_rate_limit({user.id, conversation.id}, :send_message) do
    :ok ->
      # Security check: Verify user is a participant in the conversation
      case get_conversation_participant(conversation.id, user.id) do
        nil ->
          ErrorHandler.authorization_error()

        _participant ->
          # Continue with existing message creation logic
          create_message_with_broadcast(conversation, attrs, user)
      end

    {:error, :rate_limited} ->
      ErrorHandler.rate_limit_error()
  end
end

# Extract the message creation and broadcasting logic to a separate function:
defp create_message_with_broadcast(conversation, attrs, user) do
  ErrorHandler.with_error_handling(fn ->
    Repo.transaction(fn ->
      with {:ok, message} <-
             %DirectMessage{}
             |> DirectMessage.changeset(
               Map.merge(attrs, %{conversation_id: conversation.id, user_id: user.id})
             )
             |> Repo.insert(),
           {:ok, _} <- update_conversation_last_message(conversation, message.inserted_at) do
        message = message |> Repo.preload([:user, :attachments])
        broadcast_new_message(conversation, message)
        message
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end, user_id: user.id)
end
```

### 3. Replace Permission Checking Logic

**Replace permission checking functions:**

```elixir
# Replace can_manage_conversation? function:
defp can_manage_conversation?(conversation, current_user) do
  Authorization.can_manage_conversation?(current_user, conversation)
end

# Replace can_invite_to_conversation? function:
defp can_invite_to_conversation?(conversation, current_user) do
  Authorization.can_invite_to_conversation?(current_user, conversation)
end

# Replace validate_role_promotion function:
defp validate_role_promotion(current_role, new_role) do
  Authorization.validate_role_promotion(current_role, new_role)
end

# Replace role_has_permission? function:
defp role_has_permission?(role, permission) do
  Authorization.role_has_permission?(role, permission)
end

# Update promote_participant function to use Authorization:
def promote_participant(%Conversation{id: conversation_id}, target_user_id, new_role, %User{id: user_id}) do
  if Authorization.can_manage_participants?(%User{id: user_id}, %Conversation{id: conversation_id}) do
    with {:ok, target_participant} when not is_nil(target_participant) <- get_conversation_participant(conversation_id, target_user_id),
         :ok <- Authorization.validate_role_promotion(target_participant.role, new_role) do

      target_participant
      |> ConversationParticipant.changeset(%{role: new_role})
      |> Repo.update()
    else
      {:ok, _role} -> ErrorHandler.authorization_error()
      nil -> ErrorHandler.not_found_error("Participant")
      {:error, reason} -> ErrorHandler.normalize_error(reason)
    end
  else
    ErrorHandler.authorization_error()
  end
end
```

### 4. Replace Error Handling

**Update error handling throughout the file:**

```elixir
# Replace error returns in create_conversation:
def create_conversation(attrs, opts) do
  ErrorHandler.with_error_handling(fn ->
    # Extract options
    participants = Keyword.get(opts, :participants, [])
    participant_ids = Keyword.get(opts, :participant_ids, [])
    creator = Keyword.get(opts, :creator)
    conversation_type = Map.get(attrs, "type") || Map.get(attrs, :type) || "direct"

    # Continue with existing logic
    create_conversation_with_validation(attrs, participants, participant_ids, creator, conversation_type)
  end, user_id: get_user_id_from_opts(opts))
end

# Extract the conversation creation logic:
defp create_conversation_with_validation(attrs, participants, participant_ids, creator, conversation_type) do
  # Validate that we don't have conflicting participant specifications
  cond do
    participants != [] and participant_ids != [] ->
      ErrorHandler.validation_error("cannot specify both participants and participant_ids")

    participants == [] and participant_ids == [] ->
      # Check if this was called from create_conversation_with_participants with empty list
      if Map.has_key?(attrs, :_called_with_participants) do
        ErrorHandler.validation_error("must have at least 2 participants")
      else
        # Simple conversation creation without participants
        %Conversation{}
        |> Conversation.changeset(attrs)
        |> Repo.insert()
      end

    participants != [] ->
      # Create conversation with user structs
      create_conversation_with_users(attrs, participants, creator, conversation_type)

    participant_ids != [] ->
      # Create conversation with user IDs
      create_conversation_with_ids(attrs, participant_ids, conversation_type)
  end
end
```

### 5. Replace Pagination and Search

**Update list_direct_messages function:**

```elixir
def list_direct_messages(conversation_or_id, opts \\ [])

def list_direct_messages(%Conversation{} = conversation, opts) do
  list_direct_messages(conversation.id, opts)
end

def list_direct_messages(conversation_id, opts) when is_integer(conversation_id) do
  # Authorization check
  user_id = Keyword.get(opts, :current_user_id)

  if user_id && get_conversation_participant(conversation_id, user_id) do
    # Use QueryBuilder to build the query
    base_query = QueryBuilder.messages_query(
      schema: DirectMessage,
      conversation_id: conversation_id,
      include_reactions: true,
      include_attachments: true
    )
    
    # Apply cursor-based pagination
    result = QueryBuilder.cursor_paginate_query(base_query, opts)
    
    # Transform result to expected format
    %{entries: result.entries, metadata: result.metadata}
  else
    %{entries: [], metadata: %{has_next: false, has_previous: false}}
  end
end
```

**Update search_direct_messages function:**

```elixir
def search_direct_messages(conversation_id, query, opts \\ []) do
  # Authorization check
  user_id = Keyword.get(opts, :current_user_id)

  if user_id && get_conversation_participant(conversation_id, user_id) do
    # Use QueryBuilder for search
    base_query = QueryBuilder.messages_query(
      schema: DirectMessage,
      conversation_id: conversation_id,
      include_reactions: true,
      include_attachments: true
    )
    
    search_query = QueryBuilder.search_query(base_query, query, search_field: :body)
    result = QueryBuilder.cursor_paginate_query(search_query, opts)
    
    # Transform result to expected format
    %{entries: result.entries, metadata: result.metadata}
  else
    %{entries: [], metadata: %{has_next: false, has_previous: false}}
  end
end
```

### 6. Replace Broadcasting Logic

**Update broadcasting functions:**

```elixir
defp broadcast_new_message(conversation, message) do
  topic = Constants.pubsub_topic(:conversation, conversation.id)
  
  enriched_message =
    Map.put(message, :broadcast_at, DateTime.utc_now() |> DateTime.truncate(:second))

  # Broadcast with error handling
  try do
    Phoenix.PubSub.broadcast!(
      @pubsub,
      topic,
      {:new_direct_message, enriched_message}
    )
  rescue
    error ->
      Logger.error("Failed to broadcast new message: #{inspect(error)}",
        conversation_id: conversation.id,
        message_id: message.id
      )
  end
end

# Update other broadcasting functions similarly
defp broadcast_message_update(message) do
  topic = Constants.pubsub_topic(:conversation, message.conversation_id)
  
  try do
    Phoenix.PubSub.broadcast!(
      @pubsub,
      topic,
      {:updated_direct_message, message}
    )
  rescue
    error ->
      Logger.error("Failed to broadcast message update: #{inspect(error)}",
        message_id: message.id
      )
  end
end

defp broadcast_message_deletion(message) do
  topic = Constants.pubsub_topic(:conversation, message.conversation_id)
  
  try do
    Phoenix.PubSub.broadcast!(
      @pubsub,
      topic,
      {:direct_message_deleted, message}
    )
  rescue
    error ->
      Logger.error("Failed to broadcast message deletion: #{inspect(error)}",
        message_id: message.id
      )
  end
end
```

### 7. Replace Validation Logic

**Update validation functions:**

```elixir
defp validate_participant_limits("direct", count) when count > 2 do
  ErrorHandler.validation_error("direct conversations can have maximum 2 participants")
end

defp validate_participant_limits("direct", count) when count < 2 do
  ErrorHandler.validation_error("must have at least 2 participants")
end

defp validate_participant_limits("group", count) when count < 2 do
  ErrorHandler.validation_error("must have at least 2 participants")
end

defp validate_participant_limits("group", count) when count > @max_participants do
  ErrorHandler.validation_error("group conversations can have maximum #{@max_participants} participants")
end

defp validate_participant_limits(_type, count) when count < 2 do
  ErrorHandler.validation_error("must have at least 2 participants")
end

defp validate_participant_limits(_type, _count), do: :ok
```

### 8. Replace Error Messages

**Update error messages throughout the file:**

```elixir
# Replace error messages with Constants
def create_conversation_invite(conversation, invitee_id, inviter) do
  case get_user_role_in_conversation(conversation.id, inviter.id) do
    {:ok, inviter_role} -> 
      if Authorization.role_has_permission?(inviter_role, :invite_participants) do
        # Continue with invitation logic
      else
        ErrorHandler.authorization_error()
      end
    {:error, _reason} -> 
      ErrorHandler.authorization_error()
  end
end

# Replace other error messages similarly
def accept_conversation_invite(token, user) do
  case Repo.get_by(ConversationInvite, token: token, invitee_id: user.id, status: "pending") do
    nil ->
      ErrorHandler.not_found_error("Invitation")

    invite ->
      if DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt do
        # Expire the invite
        invite
        |> ConversationInvite.changeset(%{status: "expired"})
        |> Repo.update()

        ErrorHandler.error_with_message("Invitation has expired")
      else
        # Continue with acceptance logic
      end
  end
end
```

## Testing the Refactored Code

After making these changes:

1. **Run the DirectMessaging tests**:
   ```bash
   mix test test/slap/direct_messaging_test.exs
   mix test test/slap/direct_messaging_group_test.exs
   ```

2. **Run the integration tests**:
   ```bash
   mix test test/slap_web/live/direct_messaging_component_test.exs
   mix test test/slap_web/live/end_to_end_dm_test.exs
   ```

3. **Check for compilation errors**:
   ```bash
   mix compile
   ```

4. **Test the specific functionality**:
   - Create conversations
   - Send direct messages
   - Search messages
   - Rate limiting
   - Permission checks

## Expected Benefits

After refactoring:

1. **Reduced code size** from over 1,100 lines to approximately 700-800 lines
2. **Improved maintainability** with centralized logic
3. **Consistent error handling** across the context
4. **Better testability** with smaller, focused functions
5. **Easier to extend** with new features

## Conclusion

This refactoring guide provides specific instructions for updating the DirectMessaging context to use the shared modules. By following these steps, we can significantly reduce code duplication and improve maintainability while preserving all existing functionality.