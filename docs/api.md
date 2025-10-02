# API Documentation

This document provides a comprehensive overview of the Slap application's API, including LiveView components, context modules, and schemas.

## Table of Contents

1. [LiveView Components](./api/liveview-components.md)
2. [Context Modules](./api/contexts.md)
3. [Schemas](./api/schemas.md)
4. [Routes](./api/routes.md)
5. [Channels](./api/channels.md)

## Overview

The Slap application uses Phoenix LiveView as its primary API interface, with traditional HTTP controllers for specific operations like authentication and file serving. The API is organized into several layers:

- **LiveView Components**: Real-time UI components
- **Context Modules**: Business logic and data operations
- **Schemas**: Data structures and validation
- **Routes**: URL routing and endpoint definitions
- **Channels**: Real-time communication via WebSockets

## API Architecture

### Request Flow

1. **HTTP Request**: Client sends request to Phoenix endpoint
2. **Router**: Routes request to appropriate controller or LiveView
3. **Authentication**: User authentication via plugs
4. **LiveView/Controller**: Process request and interact with contexts
5. **Context**: Execute business logic and database operations
6. **Database**: Store and retrieve data
7. **Response**: Return rendered HTML or JSON response

### Real-time Communication

1. **WebSocket Connection**: Client connects via Phoenix LiveView
2. **Channel Subscription**: Subscribe to relevant topics
3. **Event Handling**: Process client events and server pushes
4. **PubSub Broadcasting**: Broadcast updates to subscribed clients
5. **UI Updates**: LiveView updates client interface

## Authentication

### Session-based Authentication

The application uses session-based authentication with secure tokens:

```elixir
# Authentication plug
def require_authenticated_user(conn, _opts) do
  if conn.assigns[:current_user] do
    conn
  else
    conn
    |> put_flash(:error, "You must log in to access this page.")
    |> maybe_store_return_to()
    |> redirect(to: ~p"/users/log_in")
    |> halt()
  end
end
```

### LiveView Authentication

LiveView hooks ensure user authentication:

```elixir
def on_mount(:ensure_authenticated, _params, session, socket) do
  {:cont, assign_current_user(socket, session)}
end
```

## Error Handling

### Standardized Error Responses

The application provides consistent error handling:

```elixir
defp handle_errors(conn, {:error, reason}) do
  conn
  |> put_status(:unprocessable_entity)
  |> put_view(html: SlapWeb.ErrorHTML, json: SlapWeb.ErrorJSON)
  |> render(:"422", error: reason)
end
```

### Error Logging

Errors are logged with context for debugging:

```elixir
Logger.error("Failed to process request: #{inspect(reason)}")
```

## Rate Limiting

The application implements rate limiting for sensitive operations:

```elixir
def check_rate_limit(user_id, operation) do
  case Hammer.check_rate("user:#{user_id}:#{operation}", 60_000, 10) do
    {:allow, _count} -> :ok
    {:deny, _limit} -> {:error, :rate_limited}
  end
end
```

## Response Formats

### HTML Responses

Most endpoints return HTML responses rendered by LiveView:

```elixir
def render("index.html", assigns) do
  ~H"""
  <div class="container">
    <!-- HTML content -->
  </div>
  """
end
```

### JSON Responses

Some endpoints return JSON for API operations:

```elixir
def render("error.json", %{error: error}) do
  %{errors: %{detail: error}}
end
```

## Security Headers

Security headers are automatically added to responses:

```elixir
plug :put_secure_browser_headers
```

This includes:
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection
- Strict-Transport-Security (in production)

## CORS Configuration

Cross-Origin Resource Sharing is configured for API access:

```elixir
config :slap, SlapWeb.Endpoint,
  # ... other config
  cors: [
    origin: ["http://localhost:3000"],
    max_age: 86400,
    credentials: true
  ]
```

## API Versioning

The application currently uses a single API version. Future versions can be added with URL prefixes:

```elixir
# Future API versioning
scope "/api/v1", SlapWeb do
  pipe_through :api
  
  # API routes
end
```

## Performance Considerations

### Response Caching

Static responses are cached for performance:

```elixir
plug :put_cache_control_headers, max_age: 3600
```

### Database Connection Pooling

Database connections are pooled for efficiency:

```elixir
config :slap, Slap.Repo,
  pool_size: 10,
  queue_target: 5000
```

### LiveView Optimization

LiveView processes are optimized for performance:

```elixir
config :phoenix, :live_view,
  signing_salt: "random_salt",
  # Optimize for production
  compress_transport: true
```

## Monitoring and Telemetry

### Request Metrics

Request metrics are collected via Phoenix Telemetry:

```elixir
defmetrics = [
  # Phoenix metrics
  phoenix_controller_call_duration,
  phoenix_controller_render_duration,
  phoenix_live_view_mount_duration,
  phoenix_live_view_render_duration,
  phoenix_live_view_connected_duration,
  phoenix_live_view_handle_event_duration,
  phoenix_live_view_handle_params_duration,
  phoenix_channel_join_duration,
  phoenix_channel_handle_in_duration
]
```

### Custom Metrics

Custom business metrics are tracked:

```elixir
:telemetry.execute([:slap, :message, :created], %{count: 1}, %{room_id: room.id})
```

## Testing API

### HTTP Request Testing

```elixir
def get(conn, path, params \\ %{}) do
  conn
  |> Phoenix.ConnTest.build_conn(:get, path, params)
  |> SlapWeb.Router.call(SlapWeb.Router.init([]))
end
```

### LiveView Testing

```elixir
{:ok, view, html} = live(conn, "/rooms/#{room.id}")
assert html =~ room.name
```

## API Documentation Standards

### Function Documentation

All public API functions are documented:

```elixir
@doc """
Creates a new message in a room.

## Parameters

- `room`: The room struct to create the message in
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

Functions include type specifications:

```elixir
@spec create_message(Room.t(), map(), User.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
def create_message(room, attrs, user) do
  # Implementation
end
```

This API documentation provides a comprehensive overview of the application's interfaces, making it easier for developers to understand and work with the codebase.