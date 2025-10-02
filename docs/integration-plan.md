# Slap Shared Modules Integration Plan

This document provides a detailed plan for integrating the newly created shared modules into the existing Slap codebase to replace duplicated code.

## Overview

We've created the following shared modules that need to be integrated into the existing codebase:

1. **Slap.Constants** - Centralized constants
2. **Slap.Authorization** - Unified authorization system
3. **Slap.Pagination** - Shared pagination utilities
4. **Slap.RateLimiter** - Unified rate limiting
5. **Slap.Messaging** - Common messaging patterns
6. **Slap.ErrorHandler** - Comprehensive error handling
7. **Slap.QueryBuilder** - Common query patterns
8. **SlapWeb.UIHelpers** - Shared UI components

## Integration Strategy

We'll follow the Strangler Fig Pattern for integration:

1. **Add imports** for shared modules to existing files
2. **Replace duplicated code** with calls to shared modules
3. **Run tests** to ensure functionality is preserved
4. **Remove old code** once all references are updated

## Detailed Integration Steps

### 1. Slap.Constants Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap_web/live/direct_messaging_component.ex`
- `lib/slap_web/live/chat_room_live.ex`
- `lib/slap/chat.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.Constants

# Replace rate limit constants
@default_message_limit Constants.default_message_limit()
@rate_limit_window Constants.rate_limit_window()
@rate_limit_max_messages Constants.rate_limit_max_messages()

# Replace conversation type validation
defp validate_participant_limits("direct", count) when count > 2 do
  {:error, Constants.get_error_message(:invalid_conversation_type)}
end

# Replace error messages
defp broadcast_new_message(conversation, message) do
  topic = Constants.pubsub_topic(:conversation, conversation.id)
  # ... rest of the function
end
```

**In lib/slap_web/live/direct_messaging_component.ex:**

```elixir
# Add at the top of the file
alias Slap.Constants

# Replace CSS classes
defp get_user_role_badge(role) do
  case role do
    "admin" -> Constants.get_role_badge_class("admin")
    "moderator" -> Constants.get_role_badge_class("moderator")
    "member" -> Constants.get_role_badge_class("member")
    "restricted" -> Constants.get_role_badge_class("restricted")
    _ -> ""
  end
end

# Replace error messages
def handle_event("create_group_conversation", _params, socket) do
  case DirectMessaging.create_group_conversation(...) do
    {:ok, _} -> # Success
    {:error, _reason} -> 
      put_flash(socket, :error, Constants.get_error_message(:conversation_creation_failed))
  end
end
```

### 2. Slap.Authorization Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap_web/live/direct_messaging_component.ex`
- `lib/slap/chat.ex`
- `lib/slap_web/live/chat_room_live.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.Authorization

# Replace permission checks
defp can_manage_conversation?(conversation, current_user) do
  Authorization.can_manage_conversation?(current_user, conversation)
end

# Replace role validation
defp validate_role_promotion(current_role, new_role) do
  Authorization.validate_role_promotion(current_role, new_role)
end

# Replace permission checks in functions
def promote_participant(conversation, target_user_id, new_role, current_user) do
  if Authorization.can_manage_participants?(current_user, conversation) do
    # Proceed with promotion
  else
    {:error, Constants.get_error_message(:insufficient_permissions)}
  end
end
```

**In lib/slap_web/live/direct_messaging_component.ex:**

```elixir
# Add at the top of the file
alias Slap.Authorization

# Replace permission checks in UI
defp can_manage_conversation?(conversation, current_user) do
  Authorization.can_manage_conversation?(current_user, conversation)
end

defp can_invite_to_conversation?(conversation, current_user) do
  Authorization.can_invite_to_conversation?(current_user, conversation)
end
```

### 3. Slap.RateLimiter Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap/chat.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.RateLimiter

# Replace the check_rate_limit function
def send_direct_message(conversation, attrs, user) do
  # Check rate limit before sending
  case RateLimiter.check_rate_limit({user.id, conversation.id}, :send_message) do
    :ok ->
      # Proceed with message creation
    {:error, :rate_limited} ->
      {:error, Constants.get_error_message(:rate_limit_exceeded)}
  end
end

# Remove the old check_rate_limit function (lines 845-876)
```

### 4. Slap.Pagination Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap/chat.ex`
- `lib/slap_web/live/chat_room_live.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.Pagination

# Replace list_direct_messages function
def list_direct_messages(conversation_id, opts) when is_integer(conversation_id) do
  # Authorization check
  user_id = Keyword.get(opts, :current_user_id)

  if user_id && get_conversation_participant(conversation_id, user_id) do
    # Build base query
    base_query = from(dm in DirectMessage,
      where: dm.conversation_id == ^conversation_id,
      order_by: [desc: dm.inserted_at, asc: dm.id],
      preload: [:user, :attachments]
    )
    
    # Use pagination module
    Pagination.paginate(base_query, opts)
  else
    %{entries: [], metadata: %{has_next: false, has_previous: false}}
  end
end

# Replace search_direct_messages function
def search_direct_messages(conversation_id, query, opts) do
  # Authorization check
  user_id = Keyword.get(opts, :current_user_id)

  if user_id && get_conversation_participant(conversation_id, user_id) do
    # Build base query
    base_query = from(dm in DirectMessage,
      where: dm.conversation_id == ^conversation_id,
      order_by: [desc: dm.inserted_at, asc: dm.id],
      preload: [:user, :attachments]
    )
    
    # Use search functionality from QueryBuilder or Messaging
    search_query = apply_search_filters(base_query, query)
    Pagination.paginate(search_query, opts)
  else
    %{entries: [], metadata: %{has_next: false, has_previous: false}}
  end
end
```

### 5. Slap.ErrorHandler Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap/chat.ex`
- `lib/slap_web/live/direct_messaging_component.ex`
- `lib/slap_web/live/chat_room_live.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.ErrorHandler

# Wrap functions with error handling
def create_conversation(attrs, opts) do
  ErrorHandler.with_error_handling(fn ->
    # Existing conversation creation logic
  end, user_id: Keyword.get(opts, :user_id))
end

def send_direct_message(conversation, attrs, user) do
  ErrorHandler.with_error_handling(fn ->
    # Existing message sending logic
  end, user_id: user.id)
end

# Replace error returns
defp handle_error(error) do
  case ErrorHandler.normalize_error(error) do
    {:error, :validation, message, _} -> {:error, message}
    {:error, :authorization, message, _} -> {:error, message}
    {:error, type, message, _} -> {:error, message}
  end
end
```

### 6. Slap.QueryBuilder Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap/chat.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.QueryBuilder

# Replace query building in functions
def list_direct_messages(conversation_id, opts) do
  # Use QueryBuilder to build the query
  base_query = QueryBuilder.messages_query(
    schema: DirectMessage,
    conversation_id: conversation_id,
    include_reactions: true,
    include_attachments: true
  )
  
  # Apply pagination
  QueryBuilder.paginate_query(base_query, opts)
end

def search_direct_messages(conversation_id, query, opts) do
  # Use QueryBuilder for search
  base_query = QueryBuilder.messages_query(
    schema: DirectMessage,
    conversation_id: conversation_id
  )
  
  search_query = QueryBuilder.search_query(base_query, query, search_field: :body)
  QueryBuilder.paginate_query(search_query, opts)
end
```

### 7. Slap.Messaging Integration

#### Files to Update:
- `lib/slap/direct_messaging.ex`
- `lib/slap/chat.ex`

#### Changes:

**In lib/slap/direct_messaging.ex:**

```elixir
# Add at the top of the file
alias Slap.Messaging

# Replace send_direct_message function
def send_direct_message(conversation, attrs, user) do
  Messaging.create_message(:direct, conversation, attrs, user)
end

# Replace list_direct_messages function
def list_direct_messages(conversation_id, opts) do
  conversation = get_conversation!(conversation_id)
  result = Messaging.list_messages(:direct, conversation, opts)
  
  # Transform result to expected format if needed
  result
end

# Replace search_direct_messages function
def search_direct_messages(conversation_id, query, opts) do
  conversation = get_conversation!(conversation_id)
  Messaging.search_messages(:direct, conversation, query, opts)
end
```

### 8. SlapWeb.UIHelpers Integration

#### Files to Update:
- `lib/slap_web/live/direct_messaging_component.ex`
- `lib/slap_web/live/chat_room_live.ex`
- `lib/slap_web/live/chat_room_live/sidebar_component.ex`

#### Changes:

**In lib/slap_web/live/direct_messaging_component.ex:**

```elixir
# Add at the top of the file
import SlapWeb.UIHelpers

# Replace avatar rendering
<.user_avatar user={message.user} size="normal" />

# Replace button rendering
<.primary_button phx-click="send_message">Send</.primary_button>
<.secondary_button phx-click="cancel">Cancel</.secondary_button>

# Replace unread badge
<.unread_badge count={unread_count} />

# Replace role badge
<.role_badge role={participant.role} />

# Replace message container
<.message_container>
  <.message_content>
    <.message_timestamp timestamp={message.inserted_at} />
    <.message_body body={message.body} />
  </.message_content>
</.message_container>
```

## Testing Strategy

After each integration step:

1. **Run the full test suite** to ensure functionality is preserved
2. **Check for compilation errors** and fix any issues
3. **Test the specific functionality** that was refactored
4. **Run any related integration tests**

## Rollout Plan

1. **Phase 1**: Integrate Constants and Authorization modules (low risk)
2. **Phase 2**: Integrate RateLimiter and ErrorHandler modules (medium risk)
3. **Phase 3**: Integrate Pagination and QueryBuilder modules (medium risk)
4. **Phase 4**: Integrate Messaging and UIHelpers modules (higher risk)

## Rollback Plan

If any integration causes issues:

1. **Revert the changes** to the specific file
2. **Run tests** to ensure functionality is restored
3. **Analyze the issue** and fix before retrying
4. **Consider a more gradual approach** if needed

## Expected Benefits

After integration:

1. **Reduced code duplication** across contexts
2. **Improved maintainability** with centralized logic
3. **Consistent behavior** across the application
4. **Easier testing** with smaller, focused functions
5. **Better performance** with optimized queries

## Conclusion

This integration plan provides a systematic approach to replacing duplicated code with calls to the shared modules. By following the phased rollout and testing strategy, we can minimize risk and ensure a smooth transition.