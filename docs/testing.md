# Testing

This document provides a comprehensive overview of the testing approach in the Slap application, including test structure, fixtures, and best practices.

## Table of Contents

1. [Test Structure](#test-structure)
2. [Fixtures](./testing/fixtures.md)
3. [Test Coverage](./testing/test-coverage.md)

## Overview

The Slap application uses a comprehensive testing approach to ensure reliability and maintainability. The test suite includes:

- **Unit Tests**: Test individual functions and modules
- **Integration Tests**: Test component interactions
- **LiveView Tests**: Test UI components and user interactions
- **Database Tests**: Test data operations and validations

## Testing Stack

### Testing Libraries

- **ExUnit**: Elixir's built-in testing framework
- **Phoenix.LiveViewTest**: Testing LiveView components
- **Phoenix.ConnTest**: Testing HTTP requests and responses
- **ExMachina**: Factory for test data generation
- **Bypass**: Mocking HTTP requests

### Test Configuration

```elixir
# test/test_helper.exs
ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Slap.Repo, :manual)
```

## Test Structure

### Directory Structure

```
test/
├── test_helper.exs              # Test configuration
├── support/
│   ├── conn_case.ex            # Connection test case
│   ├── data_case.ex            # Database test case
│   └── fixtures/               # Test data fixtures
│       ├── accounts_fixtures.ex
│       ├── chat_fixtures.ex
│       ├── direct_messaging_fixtures.ex
│       └── group_conversation_fixtures.ex
├── slap/
│   ├── accounts_test.exs       # Account context tests
│   ├── chat_test.exs           # Chat context tests
│   ├── direct_messaging_test.exs
│   └── uploads_test.exs
└── slap_web/
    ├── controllers/            # Controller tests
    ├── live/                   # LiveView tests
    └── components/             # Component tests
```

### Test Cases

#### DataCase

For database-related tests:

```elixir
defmodule Slap.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Slap.Repo

      import Ecto.Query
      import Slap.DataCase
      import Slap.TestHelpers
    end
  end

  setup tags do
    Slap.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Slap.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
```

#### ConnCase

For web-related tests:

```elixir
defmodule SlapWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ConnTest
      use SlapWeb, :verified_routes

      import Slap.TestHelpers
      import SlapWeb.ConnCase

      alias Slap.Repo
      alias Slap.Accounts.User
    end
  end

  setup tags do
    Slap.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
```

## Test Types

### Unit Tests

Test individual functions and modules:

```elixir
defmodule Slap.AccountsTest do
  use Slap.DataCase

  describe "register_user/1" do
    test "creates user with valid attributes" do
      attrs = %{
        email: "test@example.com",
        username: "testuser",
        password: "ValidPassword123!"
      }

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.email == "test@example.com"
      assert user.username == "testuser"
    end

    test "returns error with invalid attributes" do
      attrs = %{email: "invalid", username: "", password: "short"}

      assert {:error, %Ecto.Changeset{}} = Accounts.register_user(attrs)
    end
  end
end
```

### Integration Tests

Test component interactions:

```elixir
defmodule Slap.ChatTest do
  use Slap.DataCase

  describe "create_message/3" do
    test "creates message and broadcasts update" do
      user = user_fixture()
      room = room_fixture()
      
      # Subscribe to updates
      Phoenix.PubSub.subscribe(Slap.PubSub, "chat_room:#{room.id}")
      
      attrs = %{body: "Test message"}
      
      assert {:ok, %Message{} = message} = Chat.create_message(room, attrs, user)
      assert message.body == "Test message"
      assert message.room_id == room.id
      assert message.user_id == user.id
      
      # Verify broadcast
      assert_receive {:new_message, ^message}
    end
  end
end
```

### LiveView Tests

Test UI components and user interactions:

```elixir
defmodule SlapWeb.ChatRoomLiveTest do
  use SlapWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "ChatRoomLive" do
    setup [:register_and_log_in_user]

    test "mounts chat room with messages", %{conn: conn, user: user} do
      room = room_fixture()
      message = message_fixture(room, user)
      
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      
      assert render(view) =~ room.name
      assert render(view) =~ message.body
    end

    test "sends message", %{conn: conn, user: user} do
      room = room_fixture()
      
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      
      view
      |> form("#message-form", message: %{body: "Test message"})
      |> render_submit()
      
      assert render(view) =~ "Test message"
    end

    test "adds reaction to message", %{conn: conn, user: user} do
      room = room_fixture()
      message = message_fixture(room, user)
      
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.id}")
      
      view
      |> element("#message-#{message.id}")
      |> render_hook("add-reaction", %{"emoji" => "👍", "message_id" => message.id})
      
      assert render(view) =~ "👍"
    end
  end
end
```

### Controller Tests

Test HTTP endpoints:

```elixir
defmodule SlapWeb.UserSessionControllerTest do
  use SlapWeb.ConnCase

  describe "POST /users/log_in" do
    test "logs user in with valid credentials", %{conn: conn} do
      user = user_fixture()
      
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })
      
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "returns error with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "invalid@example.com", "password" => "invalid"}
        })
      
      response = html_response(conn, 200)
      assert response =~ "Invalid email or password"
    end
  end
end
```

## Test Helpers

### Common Test Functions

```elixir
defmodule Slap.TestHelpers do
  @moduledoc """
  Common helper functions for tests.
  """

  def register_and_log_in_user(%{conn: conn}) do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  def log_in_user(conn, user) do
    token = Slap.Accounts.generate_user_session_token(user)
    
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  def valid_user_password, do: "ValidPassword123!"

  def extract_user_token(fun) do
    {:ok, captured} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token, _] = String.split(captured.body, "[TOKEN]")
    token
  end
end
```

### Assertion Helpers

```elixir
defmodule Slap.AssertionHelpers do
  @moduledoc """
  Custom assertion helpers for tests.
  """

  import ExUnit.Assertions

  def assert_broadcast(topic, payload) do
    assert_receive {^topic, ^payload}, 1000
  end

  def assert_email_sent(to) do
    assert_email_sent(to, fn _email -> true end)
  end

  def assert_email_sent(to, matcher) do
    assert_receive {:email, email}, 1000
    assert email.to == [to]
    assert matcher.(email)
  end
end
```

## Mocking and Stubbing

### Bypass for HTTP Requests

```elixir
defmodule Slap.ExternalServiceTest do
  use Slap.DataCase
  
  test "calls external API" do
    bypass = Bypass.open(port: 1234)
    
    Bypass.expect(bypass, "GET", "/api/data", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"data": "success"}))
    end)
    
    # Configure application to use bypass port
    Application.put_env(:slap, :external_api_url, "http://localhost:1234")
    
    result = ExternalService.fetch_data()
    assert result == {:ok, %{"data" => "success"}}
  end
end
```

### Mocking Functions

```elixir
defmodule Slap.ServiceTest do
  use Slap.DataCase
  import Mox

  # Make mocks explicit
  setup :verify_on_exit!

  test "calls external service" do
    expect(Slap.ExternalServiceMock, :process_data, fn data ->
      {:ok, "processed: #{data}"}
    end)
    
    {:ok, result} = Slap.MyService.do_something("test")
    assert result == "processed: test"
  end
end
```

## Test Data Management

### Transactional Tests

Tests run in database transactions for isolation:

```elixir
defmodule Slap.DataCase do
  using do
    quote do
      alias Slap.Repo
      
      # All tests run in a transaction
      setup tags do
        Slap.DataCase.setup_sandbox(tags)
        :ok
      end
    end
  end
end
```

### Async Testing

Tests can run in parallel when possible:

```elixir
@tag :async
test "can run in parallel" do
  # Test logic
end
```

## Test Coverage

### Coverage Configuration

```elixir
# mix.exs
def project do
  [
    # ... other config
    test_coverage: [output: "cover"],
    preferred_cli_env: [coveralls: :test]
  ]
end
```

### Running Coverage

```bash
# Run tests with coverage
mix test --cover

# Generate HTML coverage report
mix coveralls.html

# Check coverage threshold
mix coveralls.html --threshold 90
```

## Performance Testing

### Benchmark Tests

```elixir
defmodule Slap.PerformanceTest do
  use ExUnit.Case
  
  @tag :benchmark
  test "message creation performance" do
    user = user_fixture()
    room = room_fixture()
    
    {time, _result} = :timer.tc(fn ->
      Enum.each(1..1000, fn _i ->
        message_fixture(room, user, %{body: "Test message"})
      end)
    end)
    
    # Assert reasonable performance
    assert time < 5_000_000  # Less than 5 seconds
  end
end
```

## Property-Based Testing

### StreamData Tests

```elixir
defmodule Slap.PropertyTest do
  use ExUnit.Case
  use StreamData
  
  test "email validation" do
    check all email <- string(:alphanumeric) do
      changeset = Slap.Accounts.User.changeset(%Slap.Accounts.User{}, %{email: email})
      
      # Valid emails should pass validation
      if String.contains?(email, "@") do
        assert changeset.valid?
      end
    end
  end
end
```

## Best Practices

### Test Organization

1. **Group related tests** with `describe` blocks
2. **Use descriptive test names** that explain what is being tested
3. **Keep tests focused** on a single behavior
4. **Use setup functions** for common test data

### Test Data

1. **Use fixtures** for consistent test data
2. **Avoid hardcoding values** in tests
3. **Clean up resources** after tests
4. **Use factories** for complex data creation

### Assertions

1. **Be specific** with assertions
2. **Test both success and failure cases**
3. **Use custom assertions** for complex validations
4. **Assert behavior, not implementation**

### Test Maintenance

1. **Keep tests fast** and focused
2. **Run tests frequently** during development
3. **Update tests** when changing code
4. **Remove obsolete tests**

## Continuous Integration

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.14'
        otp-version: '25'
    
    - name: Install Dependencies
      run: mix deps.get --only test
    
    - name: Run Tests
      run: mix test --cover
    
    - name: Upload Coverage
      uses: codecov/codecov-action@v1
```

This testing documentation provides a comprehensive overview of the testing approach in the Slap application, ensuring code quality and reliability through thorough testing practices.