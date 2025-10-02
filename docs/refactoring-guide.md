# Slap Refactoring Guide

This guide explains how to use the new shared modules to refactor the Slap codebase and maintain clean, maintainable code.

## Overview

We've implemented several shared modules to eliminate code duplication and improve maintainability:

1. **Slap.Constants** - Centralized constants for magic numbers and strings
2. **Slap.Authorization** - Unified role-based access control system
3. **Slap.Pagination** - Shared pagination utilities
4. **Slap.RateLimiter** - Unified rate limiting system
5. **Slap.Messaging** - Common messaging patterns
6. **Slap.ErrorHandler** - Comprehensive error handling
7. **Slap.QueryBuilder** - Common query patterns
8. **SlapWeb.UIHelpers** - Shared UI components and helpers

## Migration Strategy

Follow the Strangler Fig Pattern for migrating existing code:

1. Create new functionality using the shared modules
2. Gradually update existing code to use the shared modules
3. Ensure all tests pass after each change
4. Remove old code once all references are updated

## Module Usage Examples

### Constants Module

Replace magic numbers and strings with constants:

**Before:**
```elixir
@default_message_limit 50
@rate_limit_window 60_000  # 1 minute
@max_file_size 10_000_000  # 10MB
```

**After:**
```elixir
import Slap.Constants

# Use constants directly
default_message_limit()
rate_limit_window()
max_file_size()
```

### Authorization Module

Replace scattered permission checks:

**Before:**
```elixir
defp can_manage_conversation?(conversation, current_user) do
  case DirectMessaging.get_user_role_in_conversation(conversation.id, current_user.id) do
    {:ok, role} -> role in ["admin", "moderator"]
    {:error, _} -> false
  end
end
```

**After:**
```elixir
import Slap.Authorization

# Use the unified authorization system
Authorization.can_manage_conversation?(current_user, conversation)
```

### Pagination Module

Replace duplicate pagination logic:

**Before:**
```elixir
def list_direct_messages(conversation_id, opts) do
  limit = Keyword.get(opts, :limit, 50)
  cursor_before = Keyword.get(opts, :before)
  
  query = from(dm in DirectMessage,
    where: dm.conversation_id == ^conversation_id,
    order_by: [desc: dm.inserted_at, asc: dm.id],
    limit: ^limit
  )
  
  # Apply cursor logic...
  Repo.all(query)
end
```

**After:**
```elixir
import Slap.Pagination
import Slap.QueryBuilder

def list_direct_messages(conversation_id, opts) do
  base_query = messages_query(schema: DirectMessage, conversation_id: conversation_id)
  paginate(base_query, opts)
end
```

### Rate Limiter Module

Replace inline rate limiting:

**Before:**
```elixir
defp check_rate_limit(user_id, conversation_id) do
  table_name = :rate_limit_table
  key = {user_id, conversation_id}
  now = System.monotonic_time(:millisecond)
  
  # Complex ETS logic...
end
```

**After:**
```elixir
import Slap.RateLimiter

# Use the unified rate limiter
case RateLimiter.check_rate_limit({user_id, conversation_id}, :send_message) do
  :ok -> # Proceed with operation
  {:error, :rate_limited} -> # Handle rate limit
end
```

### Messaging Module

Unify message operations:

**Before:**
```elixir
# In Chat context
def create_message(room, attrs, user) do
  # Message creation logic
  # Broadcast logic
end

# In DirectMessaging context
def send_direct_message(conversation, attrs, user) do
  # Similar message creation logic
  # Similar broadcast logic
end
```

**After:**
```elixir
import Slap.Messaging

# In Chat context
def create_message(room, attrs, user) do
  Messaging.create_message(:room, room, attrs, user)
end

# In DirectMessaging context
def send_direct_message(conversation, attrs, user) do
  Messaging.create_message(:direct, conversation, attrs, user)
end
```

### Error Handler Module

Standardize error handling:

**Before:**
```elixir
def create_conversation(attrs) do
  case Repo.insert(%Conversation{} |> Conversation.changeset(attrs)) do
    {:ok, conversation} -> {:ok, conversation}
    {:error, changeset} -> {:error, changeset}
  end
end
```

**After:**
```elixir
import Slap.ErrorHandler

def create_conversation(attrs) do
  ErrorHandler.with_error_handling(fn ->
    Repo.insert(%Conversation{} |> Conversation.changeset(attrs))
  end)
end
```

### Query Builder Module

Extract common query patterns:

**Before:**
```elixir
def search_messages(room_id, query, opts) do
  limit = Keyword.get(opts, :limit, 20)
  
  base_query = from(m in Message,
    where: m.room_id == ^room_id,
    order_by: [desc: m.inserted_at]
  )
  
  # Complex search logic...
  # Complex pagination logic...
end
```

**After:**
```elixir
import Slap.QueryBuilder
import Slap.Pagination

def search_messages(room_id, query, opts) do
  base_query = messages_query(room_id: room_id)
  search_query = search_query(base_query, query, search_field: :body)
  paginate(search_query, opts)
end
```

### UI Helpers Module

Eliminate duplicate UI code:

**Before:**
```elixir
# In multiple templates
<img 
  src={user.avatar_path || "/images/profile_avatar.png"} 
  class="w-8 h-8 rounded-full" 
  alt={user.username} 
/>

<button class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700">
  Submit
</button>
```

**After:**
```elixir
import SlapWeb.UIHelpers

# In templates
<.user_avatar user={user} size="normal" />
<.primary_button>Submit</.primary_button>
```

## Refactoring Large Functions

When refactoring large functions:

1. **Identify distinct responsibilities** within the function
2. **Extract each responsibility** into a separate function or module
3. **Use the shared modules** for common functionality
4. **Ensure each function has a single purpose**

### Example: Refactoring DirectMessaging.create_conversation

**Before:**
```elixir
def create_conversation(attrs, opts) do
  # 100+ lines handling different conversation types
  # Participant validation
  # Transaction management
  # Settings creation
  # Error handling
end
```

**After:**
```elixir
def create_conversation(attrs, opts) do
  ErrorHandler.with_error_handling(fn ->
    ConversationCreator.create(attrs, opts)
  end)
end

# In a separate module:
defmodule Slap.DirectMessaging.ConversationCreator do
  def create(attrs, opts) do
    # Extracted logic focused only on conversation creation
    # Uses shared modules for validation, rate limiting, etc.
  end
end
```

## Refactoring LiveView Components

When refactoring large LiveView components:

1. **Extract distinct UI sections** into separate components
2. **Use the UI helpers** for consistent styling
3. **Delegate business logic** to the appropriate context
4. **Use the messaging module** for real-time updates

### Example: Refactoring DirectMessagingComponent

**Before:**
```elixir
defmodule SlapWeb.DirectMessagingComponent do
  # 975 lines handling:
  # - Conversation management
  # - Message rendering
  # - Group settings
  # - Participant management
  # - Invitation handling
end
```

**After:**
```elixir
defmodule SlapWeb.DirectMessagingComponent do
  # Main component focuses on orchestration
  # Extracts separate components for:
  # - ConversationList
  # - MessageList
  # - MessageForm
  # - GroupSettings
  # - ParticipantList
  # - InvitationForm
end

defmodule SlapWeb.DirectMessaging.ConversationList do
  # Handles only conversation list functionality
end

defmodule SlapWeb.DirectMessaging.MessageList do
  # Handles only message list functionality
end
# ... and so on
```

## Testing Strategy

When refactoring:

1. **Ensure existing tests still pass** after each change
2. **Add tests for new shared modules**
3. **Test integration points** between old and new code
4. **Use property-based testing** for complex functions

## Performance Considerations

1. **Monitor database queries** after refactoring
2. **Use the query builder** to optimize queries
3. **Implement proper indexing** for common query patterns
4. **Cache frequently accessed data**

## Documentation

1. **Document public APIs** of shared modules
2. **Provide usage examples** for complex functions
3. **Update inline documentation** when refactoring
4. **Create architectural decision records** for major changes

## Next Steps

1. **Start with low-risk modules** like Constants and UIHelpers
2. **Gradually migrate business logic** to use shared modules
3. **Refactor the largest components** last
4. **Continuously monitor** for regressions or performance issues

## Conclusion

By following this refactoring guide and using the shared modules, we can:

- Reduce code duplication
- Improve maintainability
- Ensure consistent behavior across the application
- Make it easier to add new features
- Reduce the likelihood of bugs

The key is to make small, incremental changes while ensuring all tests pass throughout the process.