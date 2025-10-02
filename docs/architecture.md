# Architecture Overview

This document provides a comprehensive overview of the Slap application architecture, including its structure, technology stack, and design patterns.

## Application Structure

Slap follows the standard Phoenix application structure with some additional organization for better separation of concerns:

```
slap/
├── lib/
│   ├── slap/                    # Domain contexts and business logic
│   │   ├── accounts/           # User authentication and management
│   │   ├── chat/               # Chat-related schemas and data structures
│   │   ├── accounts.ex         # User authentication context
│   │   ├── chat.ex             # Chat room context
│   │   ├── direct_messaging.ex # Direct messaging context
│   │   ├── uploads.ex          # File upload handling
│   │   └── application.ex      # OTP application supervisor
│   ├── slap_web/               # Web layer (controllers, views, LiveView)
│   │   ├── components/         # Reusable UI components
│   │   ├── live/               # LiveView modules
│   │   │   ├── chat_room_live/ # Chat room LiveView components
│   │   │   └── shared/         # Shared LiveView components
│   │   ├── channels/           # Phoenix channels for real-time
│   │   ├── controllers/        # Traditional controllers
│   │   ├── router.ex           # Application routes
│   │   └── endpoint.ex         # Phoenix endpoint
│   ├── slap.ex                 # Main application module
│   └── slap_web.ex             # Web interface definitions
├── assets/                     # Frontend assets (JS, CSS)
├── config/                     # Configuration files
├── priv/                       # Private assets (migrations, static files)
└── test/                       # Test suite
```

## Technology Stack

### Backend

- **Elixir 1.14+**: Functional programming language
- **Phoenix 1.7.18**: Web framework
- **Phoenix LiveView 1.0.0**: Real-time UI updates
- **Ecto 3.10**: Database wrapper and query language
- **PostgreSQL**: Primary database
- **Phoenix PubSub**: Real-time messaging
- **Bandit**: Web server

### Frontend

- **Tailwind CSS**: Utility-first CSS framework
- **ESBuild**: JavaScript bundler
- **Phoenix LiveView**: Server-side rendering with real-time updates
- **WebRTC**: Voice chat functionality

### Key Dependencies

```elixir
{:phoenix, "~> 1.7.18"}
{:phoenix_live_view, "~> 1.0.0"}
{:ecto_sql, "~> 3.10"}
{:postgrex, ">= 0.0.0"}
{:bcrypt_elixir, "~> 3.0"}
{:tailwind, "~> 0.2"}
{:esbuild, "~> 0.8"}
{:paginator, "~> 1.2.0"}
{:timex, "~> 3.7"}
```

## Design Patterns

### Context Pattern

Slap follows Phoenix's context pattern to organize business logic:

- **`Slap.Accounts`**: User authentication, registration, and profile management
- **`Slap.Chat`**: Chat room management, messages, and reactions
- **`Slap.DirectMessaging`**: Direct conversations and private messages
- **`Slap.Uploads`**: File upload handling and validation

### LiveView Architecture

The application heavily relies on Phoenix LiveView for real-time functionality:

1. **Main LiveView Processes**:
   - `ChatRoomLive`: Main chat interface
   - `DirectMessagingComponent`: Direct messaging interface
   - `VoiceChatLive`: Voice chat interface

2. **Component Architecture**:
   - Modular components for specific UI elements
   - State management through LiveView sockets
   - Real-time updates via PubSub broadcasts

### Real-time Communication

Slap uses Phoenix PubSub for real-time messaging:

- **Room Topics**: `"chat_room:#{room_id}"` for room-specific messages
- **Conversation Topics**: `"conversation:#{conversation_id}"` for direct messages
- **User Topics**: `"direct_messages:#{user_id}"` for user-specific notifications
- **Voice Topics**: `"voice:#{user_id}"` for voice call signaling

### Database Design

The database schema is designed for:

1. **Performance**: Optimized indexes for common queries
2. **Scalability**: Efficient pagination and query patterns
3. **Data Integrity**: Proper foreign key relationships
4. **Real-time**: Timestamps for tracking message order

## Key Architectural Decisions

### 1. LiveView First Approach

- Server-side rendering with minimal client-side JavaScript
- Real-time updates without writing frontend code
- Reduced complexity in client-side state management

### 2. Context-Based Business Logic

- Clear separation between web layer and business logic
- Testable and maintainable code organization
- Easy to understand data flow

### 3. Optimized Database Queries

- Efficient pagination with cursor-based approach
- Strategic indexing for performance
- Query optimization for real-time features

### 4. Modular Component Design

- Reusable UI components
- Clear component boundaries
- Consistent component interfaces

## Data Flow

### Message Flow

1. User submits message via LiveView form
2. Message validated and created in database
3. PubSub broadcast to relevant topic
4. All connected clients receive update
5. UI updates via LiveView stream operations

### Authentication Flow

1. User registers/logs in through authentication LiveViews
2. Session token created and stored
3. User data loaded and attached to LiveView socket
4. Subsequent requests authenticated via session

### File Upload Flow

1. User selects file in upload form
2. File validated (type, size, etc.)
3. File copied to secure storage location
4. Database record created with file reference
5. File served as static asset

## Performance Considerations

### Database Optimization

- Strategic indexing for common query patterns
- Efficient pagination for large datasets
- Query optimization for real-time updates

### Real-time Scaling

- Phoenix PubSub for distributed messaging
- Connection pooling for WebSocket connections
- Efficient message broadcasting

### Frontend Optimization

- Tailwind CSS purging for minimal CSS
- JavaScript bundling and minification
- Static asset compression

## Security Architecture

### Authentication Security

- BCrypt password hashing
- Secure session token management
- CSRF protection
- Secure cookie settings

### Data Protection

- Input validation and sanitization
- SQL injection prevention via Ecto
- File upload security measures
- XSS prevention through proper escaping

### Authorization

- Route-level access control
- Resource ownership validation
- Permission checking in business logic

## Monitoring and Observability

### Telemetry

- Phoenix Telemetry for performance metrics
- Custom telemetry for business metrics
- Database query monitoring

### Logging

- Structured logging with context
- Error tracking and reporting
- Performance monitoring

## Future Architecture Considerations

### Scalability

- Database sharding for large datasets
- Caching strategies for frequently accessed data
- Background job processing for heavy operations

### Feature Expansion

- Plugin architecture for extensible features
- API versioning for external integrations
- Microservice decomposition for specific domains

This architecture provides a solid foundation for the current features while allowing for future growth and expansion.