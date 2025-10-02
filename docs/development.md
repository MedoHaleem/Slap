# Development Guidelines

This document provides comprehensive guidelines for contributing to the Slap application, including code standards, best practices, and development workflow.

## Table of Contents

1. [Code Standards](./development/code-standards.md)
2. [Contributing](./development/contributing.md)
3. [Debugging](./development/debugging.md)

## Overview

These guidelines ensure consistency, quality, and maintainability of the Slap codebase. They cover:

- Code formatting and style
- Testing requirements
- Git workflow
- Code review process
- Documentation standards

## Development Environment

### Prerequisites

Before contributing to Slap, ensure you have:

- Elixir 1.14+
- Erlang/OTP 25+
- PostgreSQL 12+
- Node.js 16+
- Git

### Setup Instructions

1. Fork the repository
2. Clone your fork locally
3. Set up the development environment:

```bash
git clone https://github.com/your-username/slap.git
cd slap
mix setup
mix phx.server
```

## Code Standards

### Elixir Code Style

Follow the official Elixir style guide:

```elixir
# Good: Use pipe operator
result = data |> process() |> transform()

# Good: Pattern matching in function heads
def process(%User{active: true} = user), do: do_something(user)
def process(%User{active: false}), do: :inactive

# Good: Descriptive variable names
def calculate_user_metrics(user_list) do
  # Implementation
end

# Bad: Single-letter variable names
def calc(u) do
  # Implementation
end
```

### Module Organization

Organize modules logically:

```elixir
# Good: Group related functions
defmodule Slap.Chat do
  # Public API
  def create_message(room, attrs, user), do: # ...
  def list_messages(room, opts \\ []), do: # ...
  
  # Private helpers
  defp broadcast_message(message), do: # ...
  defp validate_message(attrs), do: # ...
end
```

### Documentation Standards

Document all public functions:

```elixir
@doc """
Creates a new message in a chat room.

## Parameters
- `room`: The room struct where the message will be created
- `attrs`: Map of message attributes (e.g., %{body: "Hello"})
- `user`: The user creating the message

## Returns
- `{:ok, message}` on success
- `{:error, changeset}` on failure

## Examples
    iex> create_message(room, %{body: "Hello"}, user)
    {:ok, %Message{}}
"""
def create_message(room, attrs, user) do
  # Implementation
end
```

### Type Specifications

Add type specifications to public functions:

```elixir
@spec create_message(Chat.Room.t(), map(), User.t()) :: 
  {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
def create_message(room, attrs, user) do
  # Implementation
end
```

## Testing Standards

### Test Coverage

- Maintain at least 90% test coverage
- Test all public functions
- Test both success and failure cases
- Test edge cases and error conditions

### Test Structure

Organize tests with descriptive groups:

```elixir
defmodule Slap.ChatTest do
  use Slap.DataCase

  describe "create_message/3" do
    test "creates message with valid attributes" do
      # Test implementation
    end

    test "returns error with invalid attributes" do
      # Test implementation
    end

    test "broadcasts message after creation" do
      # Test implementation
    end
  end
end
```

### Test Naming

Use descriptive test names that explain what is being tested:

```elixir
# Good: Descriptive test name
test "creates message and broadcasts to room subscribers"

# Bad: Vague test name
test "works"
```

### Test Data

Use fixtures for consistent test data:

```elixir
defmodule SlapWeb.ChatRoomLiveTest do
  use SlapWeb.ConnCase
  import Slap.ChatFixtures

  test "displays messages in room", %{conn: conn} do
    room = room_fixture()
    message = message_fixture(room)
    
    # Test implementation
  end
end
```

## Git Workflow

### Branch Naming

Use descriptive branch names:

```bash
# Good: Descriptive branch names
feature/direct-messaging
fix/authentication-bug
refactor/chat-context

# Bad: Vague branch names
stuff
fix
branch1
```

### Commit Messages

Follow conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

Examples:

```
feat(chat): add message reactions

Add ability for users to react to messages with emojis.
Reactions are stored in a separate table and broadcast
in real-time to all room participants.

Closes #123
```

### Commit Types

- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring
- `style`: Code style changes (formatting, etc.)
- `test`: Adding or updating tests
- `docs`: Documentation changes
- `chore`: Maintenance tasks

### Pull Request Process

1. Create a feature branch from `main`
2. Make your changes with small, logical commits
3. Ensure all tests pass
4. Update documentation if needed
5. Create a pull request with:
   - Clear title and description
   - Reference to related issues
   - Screenshots for UI changes
   - Testing instructions

## Code Review Guidelines

### Review Checklist

When reviewing code, check for:

- [ ] Code follows style guidelines
- [ ] Tests are comprehensive and passing
- [ ] Documentation is updated
- [ ] No sensitive information is exposed
- [ ] Performance implications are considered
- [ ] Security implications are considered
- [ ] Error handling is appropriate

### Review Feedback

Provide constructive feedback:

```markdown
**Suggestion**: Consider using pattern matching here instead of `if/else`.

**Reason**: Pattern matching is more idiomatic in Elixir and makes the code more readable.

**Example**:
```elixir
# Instead of:
if user.active do
  process_active_user(user)
else
  process_inactive_user(user)
end

# Use:
def process_user(%User{active: true} = user), do: process_active_user(user)
def process_user(%User{active: false} = user), do: process_inactive_user(user)
```
```

## Performance Guidelines

### Database Queries

- Use Ecto's query syntax instead of raw SQL when possible
- Avoid N+1 queries with proper preloading
- Use database indexes for frequently queried fields
- Consider pagination for large datasets

```elixir
# Good: Preload associations to avoid N+1
messages = 
  from(m in Message, 
    where: m.room_id == ^room_id,
    preload: [:user, :reactions])
  |> Repo.all()

# Bad: N+1 query
messages = 
  from(m in Message, where: m.room_id == ^room_id)
  |> Repo.all()

Enum.each(messages, fn message ->
  user = Repo.get(User, message.user_id)  # N+1 query!
  # Process message with user
end)
```

### Memory Usage

- Avoid loading large datasets into memory
- Use streams for processing large collections
- Be mindful of process memory usage

```elixir
# Good: Use streams for large collections
large_file
|> File.stream!()
|> Stream.map(&process_line/1)
|> Stream.filter(&keep_line?/1)
|> Enum.into([])

# Bad: Load entire file into memory
large_file
|> File.read!()
|> String.split("\n")
|> Enum.map(&process_line/1)
```

## Security Guidelines

### Input Validation

- Validate all user input
- Use Ecto changesets for data validation
- Sanitize user-generated content

```elixir
# Good: Use changesets for validation
def create_message(attrs) do
  %Message{}
  |> Message.changeset(attrs)
  |> Repo.insert()
end

# Bad: Direct database insertion without validation
def create_message(attrs) do
  Repo.insert(%Message{body: attrs.body})
end
```

### Authentication and Authorization

- Check user permissions before actions
- Use proper authentication plugs
- Validate resource ownership

```elixir
# Good: Check permissions
def delete_message(message_id, user) do
  message = get_message!(message_id)
  
  if message.user_id == user.id do
    Repo.delete(message)
  else
    {:error, :unauthorized}
  end
end

# Bad: No authorization check
def delete_message(message_id) do
  message = get_message!(message_id)
  Repo.delete(message)
end
```

## Documentation Standards

### Module Documentation

Document all modules with a clear purpose:

```elixir
defmodule Slap.Chat do
  @moduledoc """
  The Chat context handles all chat-related functionality including:
  
  - Room management
  - Message creation and retrieval
  - User presence tracking
  - Real-time updates
  
  This context provides a clean API for the web layer to interact
  with chat functionality without exposing database details.
  """
  
  # Module implementation
end
```

### Function Documentation

Document all public functions with:

- Purpose description
- Parameter descriptions
- Return value descriptions
- Usage examples

```elixir
@doc """
Lists messages in a room with pagination support.

## Parameters
- `room`: The room struct to fetch messages from
- `opts`: Keyword list of options
  - `:page` - Page number (default: 1)
  - `:per_page` - Messages per page (default: 20)

## Returns
- `{:ok, messages}` - List of messages with pagination metadata
- `{:error, reason}` - Error if room doesn't exist

## Examples
    iex> list_messages(room, page: 2, per_page: 10)
    {:ok, %{messages: [...], total_pages: 5, current_page: 2}}
"""
def list_messages(room, opts \\ []) do
  # Implementation
end
```

### Inline Comments

Add inline comments for complex logic:

```elixir
def calculate_unread_count(room, user) do
  # Get the last read message ID for this user in this room
  last_read_id = get_last_read_id(room, user)
  
  # Count messages newer than the last read message
  # This query is optimized with an index on (room_id, inserted_at)
  count = 
    from(m in Message,
      where: m.room_id == ^room.id and m.id > ^last_read_id
    )
    |> Repo.aggregate(:count, :id)
  
  count
end
```

## Debugging Guidelines

### Logging

Use structured logging with context:

```elixir
# Good: Structured logging with context
Logger.error("Failed to create message", 
  user_id: user.id, 
  room_id: room.id, 
  errors: changeset.errors
)

# Bad: Unstructured logging
Logger.error("Something went wrong")
```

### Debugging Tools

Use appropriate debugging tools:

- `IO.inspect/1` for quick debugging
- `IEx.pry/0` for interactive debugging
- Phoenix LiveDashboard for monitoring
- Ecto debug mode for SQL logging

```elixir
# Debug with IO.inspect
result = complex_function(data) |> IO.inspect(label: "Result")

# Interactive debugging
def some_function(param) do
  require IEx; IEx.pry()
  # Execution will pause here for debugging
  result = do_something(param)
  result
end
```

### Error Handling

Handle errors gracefully with proper error messages:

```elixir
# Good: Specific error handling
def process_message(message) do
  case validate_message(message) do
    {:ok, valid_message} ->
      send_message(valid_message)
    
    {:error, :too_long} ->
      {:error, "Message is too long (max 2000 characters)"}
    
    {:error, :empty} ->
      {:error, "Message cannot be empty"}
  end
end

# Bad: Generic error handling
def process_message(message) do
  try do
    send_message(message)
  rescue
    _ -> {:error, "Failed to process message"}
  end
end
```

## Contributing Guidelines

### Before Contributing

1. Read the existing documentation
2. Set up your development environment
3. Run the test suite to ensure everything works
4. Check existing issues and pull requests

### Making Changes

1. Create a new branch for your feature
2. Make your changes with small, focused commits
3. Add or update tests for your changes
4. Update documentation as needed
5. Ensure all tests pass
6. Run code formatter
7. Create a pull request

### Pull Request Template

Use this template for pull requests:

```markdown
## Description
Brief description of the changes made.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] All tests pass
- [ ] New tests added for new functionality
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes without discussion
```

This development guidelines document provides comprehensive standards and best practices for contributing to the Slap application, ensuring code quality, consistency, and maintainability.