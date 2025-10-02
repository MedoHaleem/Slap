# User Authentication System

This document provides a comprehensive overview of the user authentication system in Slap, including registration, login, session management, and security features.

## Overview

The authentication system is built using Phoenix's built-in authentication generators with customizations for the chat application. It provides:

- User registration with email and password
- Session-based authentication with remember me functionality
- Password reset and email confirmation
- User profile management with avatar uploads
- Secure password handling with bcrypt

## Architecture

### Context Module

The authentication logic is centralized in the [`Slap.Accounts`](../../lib/slap/accounts.ex) context module, which provides:

- User registration and authentication functions
- Password management and reset
- Email confirmation workflows
- Session token management

### Schema Module

The [`Slap.Accounts.User`](../../lib/slap/accounts/user.ex) schema defines the user data structure and validation rules.

### Web Layer

Authentication in the web layer is handled by:

- [`SlapWeb.UserAuth`](../../lib/slap_web/user_auth.ex) - Authentication plugs and helpers
- [`SlapWeb.UserAuth`](../../lib/slap_web/user_auth.ex) - LiveView authentication hooks
- Authentication LiveViews for registration, login, and settings

## User Registration

### Registration Flow

1. User fills out the registration form with email, username, and password
2. Server validates the input and creates a new user account
3. Confirmation email is sent to the user's email address
4. User clicks confirmation link to activate their account
5. User can now log in to the application

### Registration Form Fields

- **Email**: Valid email address (unique)
- **Username**: Unique identifier for the user (3-20 characters)
- **Password**: Minimum 12 characters with validation

### Registration Implementation

```elixir
# In Slap.Accounts
def register_user(attrs) do
  %User{}
  |> User.registration_changeset(attrs)
  |> Repo.insert()
end
```

### Validation Rules

```elixir
def registration_changeset(user, attrs, opts \\ []) do
  user
  |> cast(attrs, [:email, :username, :password])
  |> validate_email()
  |> validate_password()
  |> validate_username()
  |> put_password_hash()
  |> put_change(:confirmed_at, nil)
end
```

## User Login

### Login Flow

1. User enters email/username and password
2. Server validates credentials against the database
3. If valid, a session token is created and stored
4. User is redirected to the main application
5. Session is maintained across requests

### Login Methods

Users can log in using either:
- Email address and password
- Username and password

### Login Implementation

```elixir
def get_authenticated_user(email_or_username, password) do
  user = Repo.get_by(User, [email: email_or_username]) || 
         Repo.get_by(User, [username: email_or_username])
  
  if user && User.valid_password?(user, password) do
    user
  else
    nil
  end
end
```

## Session Management

### Session Tokens

Session tokens are used to maintain user authentication across requests:

- Tokens are stored in the session cookie
- Tokens have an expiration time (configurable)
- Tokens are securely generated and validated

### Session Implementation

```elixir
def generate_user_session_token(user) do
  {token, user_token} = UserToken.build_session_token(user)
  Repo.insert!(user_token)
  token
end

def get_user_by_session_token(token) do
  {:ok, query} = UserToken.verify_session_token_query(token)
  Repo.one(query)
end
```

### Remember Me Functionality

Users can choose to stay logged in across browser sessions:

- Extends token expiration time
- Stores token in persistent cookie
- Automatically logs user in on return visits

## Password Management

### Password Hashing

Passwords are securely hashed using bcrypt:

```elixir
def put_password_hash(changeset) do
  case changeset do
    %Ecto.Changeset{valid?: true, changes: %{password: pass}} ->
      put_change(changeset, :hashed_password, Bcrypt.hash_pwd_salt(pass))
    _ ->
      changeset
  end
end
```

### Password Reset

Users can reset forgotten passwords:

1. User requests password reset with their email
2. Server generates reset token and sends email
3. User clicks reset link in email
4. User enters new password
5. Password is updated and user is logged in

### Password Reset Implementation

```elixir
def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun) do
  {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
  Repo.insert!(user_token)
  UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
end
```

## Email Confirmation

### Confirmation Flow

1. User registers for an account
2. Confirmation email is sent with unique token
3. User clicks confirmation link
4. Token is validated and account is confirmed
5. User can now fully use the application

### Confirmation Implementation

```elixir
def confirm_user(token) do
  with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
       %User{} = user <- Repo.one(query),
       {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
    {:ok, user}
  else
    _ -> :error
  end
end
```

## User Profile Management

### Profile Fields

Users can manage the following profile information:

- **Email**: Change email address with confirmation
- **Username**: Update display username
- **Password**: Change password with current password verification
- **Avatar**: Upload profile picture

### Avatar Upload

Users can upload profile pictures:

- Supported formats: JPEG, PNG, GIF
- Maximum file size: 2MB
- Images are resized and optimized
- Stored in `priv/static/uploads/avatars/`

### Avatar Implementation

```elixir
def save_user_avatar_path(user, avatar_path) do
  user
  |> User.avatar_changeset(%{avatar_path: avatar_path})
  |> Repo.update()
end
```

## Security Features

### Password Security

- Minimum 12 character password requirement
- Password complexity validation
- Secure bcrypt hashing with salt
- Password change requires current password verification

### Session Security

- Secure session token generation
- Configurable token expiration
- Session invalidation on logout
- CSRF protection

### Email Security

- Email confirmation required for account activation
- Secure token generation for email operations
- Token expiration for email operations
- Rate limiting on email requests

### Input Validation

- Email format validation
- Username format and length validation
- Password strength validation
- SQL injection prevention via Ecto

## Authentication LiveViews

### UserRegistrationLive

Handles new user registration:

- Form validation and error display
- Duplicate email/username detection
- Success redirect after registration
- Email confirmation instructions

### UserLoginLive

Handles user authentication:

- Email/username and password input
- Remember me checkbox
- Error handling for invalid credentials
- Redirect to intended destination

### UserSettingsLive

Manages user profile settings:

- Email change with confirmation
- Password change with current verification
- Username updates
- Avatar upload and management

### UserForgotPasswordLive

Handles password reset requests:

- Email input for reset request
- Success message display
- Rate limiting to prevent abuse

### UserResetPasswordLive

Handles password reset form:

- Token validation
- New password input and confirmation
- Password strength validation
- Automatic login after reset

## Authentication Helpers

### Plugs

Authentication is enforced using plugs:

```elixir
# Require authenticated user
plug :require_authenticated_user

# Redirect if already authenticated
plug :redirect_if_user_is_authenticated

# Fetch current user
plug :fetch_current_user
```

### LiveView Hooks

LiveView authentication is handled with hooks:

```elixir
# Ensure user is authenticated
on_mount :ensure_authenticated

# Redirect if user is already authenticated
on_mount :redirect_if_user_is_authenticated
```

### Helper Functions

Common authentication helpers:

```elixir
# Check if user is authenticated
def current_user_assigns(socket)

# Redirect to login page
def redirect_to_login(socket)

# Log in user
def log_in_user(conn, user, params \\ %{})

# Log out user
def log_out_user(conn)
```

## Email Notifications

### Email Types

The system sends several types of emails:

- **Confirmation Instructions**: Account activation
- **Password Reset**: Password recovery
- **Email Change**: Email address update confirmation

### Email Implementation

Emails are sent using Swoosh and the UserNotifier module:

```elixir
defmodule Slap.Accounts.UserNotifier do
  def deliver_confirmation_instructions(user, url) do
    # Send confirmation email
  end
  
  def deliver_reset_password_instructions(user, url) do
    # Send password reset email
  end
  
  def deliver_update_email_instructions(user, url) do
    # Send email update confirmation
  end
end
```

## Configuration

### Authentication Settings

Authentication behavior can be configured in `config/config.exs`:

```elixir
config :slap, Slap.Repo,
  # Database configuration

config :slap, SlapWeb.Endpoint,
  # Endpoint configuration

config :slap, :pow,
  # Pow configuration (if used)
```

### Session Configuration

Session settings in `config/config.exs`:

```elixir
config :slap, SlapWeb.Endpoint,
  live_view: [signing_salt: "random_salt"],
  session: [
    store: :cookie,
    key: "_slap_key",
    signing_salt: "random_salt"
  ]
```

## Testing Authentication

### Test Helpers

Authentication tests use fixtures and helpers:

```elixir
def register_and_log_in_user(%{conn: conn}) do
  user = user_fixture()
  %{conn: log_in_user(conn, user), user: user}
end
```

### Test Coverage

Authentication tests cover:

- User registration validation
- Login with valid/invalid credentials
- Password reset flow
- Email confirmation
- Session management
- Security edge cases

## Best Practices

1. **Always validate user input** on the server side
2. **Use secure password hashing** with bcrypt
3. **Implement proper session management** with expiration
4. **Require email confirmation** for account activation
5. **Use HTTPS** in production to protect credentials
6. **Implement rate limiting** for sensitive operations
7. **Log authentication events** for security monitoring
8. **Regularly update dependencies** for security patches

This authentication system provides a secure foundation for the chat application while maintaining a good user experience.