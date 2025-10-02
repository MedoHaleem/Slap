# Getting Started

This guide will help you set up the Slap development environment and get the application running on your local machine.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Elixir 1.14+**: [Installation Guide](https://elixir-lang.org/install.html)
- **Erlang/OTP 25+**: Usually installed with Elixir
- **PostgreSQL 12+**: [Installation Guide](https://www.postgresql.org/download/)
- **Node.js 16+**: [Installation Guide](https://nodejs.org/en/download/)
- **Git**: [Installation Guide](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

## Installation

### 1. Clone the Repository

```bash
git clone <repository-url>
cd slap
```

### 2. Install Dependencies

Install Elixir dependencies:

```bash
mix deps.get
```

Install Node.js dependencies:

```bash
cd assets
npm install
cd ..
```

### 3. Database Setup

Create and configure the database:

```bash
# Create the database
mix ecto.create

# Run migrations
mix ecto.migrate

# Seed the database with initial data
mix run priv/repo/seeds.exs
```

If you encounter database connection issues, ensure your PostgreSQL server is running and configure the connection in `config/dev.exs`.

### 4. Environment Configuration

Copy the example environment file and configure as needed:

```bash
cp .env.example .env
```

Edit the `.env` file with your local configuration.

## Development Setup

### 1. Start the Phoenix Server

You can start the Phoenix server in two ways:

**Option 1: Standard Phoenix server**
```bash
mix phx.server
```

**Option 2: Interactive Elixir with Phoenix server**
```bash
iex -S mix phx.server
```

### 2. Access the Application

Once the server is running, open your browser and navigate to:

[http://localhost:4000](http://localhost:4000)

### 3. Create a Test Account

1. Click on "Register" in the top navigation
2. Fill in your email, username, and password
3. Submit the form to create your account
4. You'll be automatically logged in

## Development Workflow

### Running Tests

Run the full test suite:

```bash
mix test
```

Run tests with coverage:

```bash
mix test --cover
```

Run specific test files:

```bash
mix test test/slap/accounts_test.exs
```

### Code Formatting

Format your code before committing:

```bash
mix format
```

### Asset Management

Build assets for development:

```bash
mix assets.build
```

Watch for asset changes during development (run in a separate terminal):

```bash
npm run dev
```

### Database Operations

Create a new migration:

```bash
mix ecto.gen.migration migration_name
```

Rollback the last migration:

```bash
mix ecto.rollback
```

Reset the database:

```bash
mix ecto.reset
```

## Development Tools

### Interactive Console

Start the application with an interactive console:

```bash
iex -S mix
```

This allows you to interact with your application code directly:

```elixir
# Get all users
Slap.Accounts.list_users()

# Create a test room
Slap.Chat.create_room(%{name: "Test Room", topic: "Testing"})

# Send a message
user = Slap.Accounts.get_user!(1)
room = Slap.Chat.get_first_room!()
Slap.Chat.create_message(room, %{body: "Hello, World!"}, user)
```

### Database Viewer

Use a PostgreSQL client like:
- [pgAdmin](https://www.pgadmin.org/)
- [DBeaver](https://dbeaver.io/)
- [TablePlus](https://tableplus.com/)

Connect to the database using the credentials in `config/dev.exs`.

### Phoenix LiveDashboard

Access the LiveDashboard for monitoring:

[http://localhost:4000/dashboard](http://localhost:4000/dashboard)

This provides insights into:
- Request metrics
- Process information
- Database queries
- Channel subscriptions

## Common Development Tasks

### Adding a New Feature

1. Create or update the relevant context module in `lib/slap/`
2. Add or modify database schemas in `lib/slap/chat/` or `lib/slap/accounts/`
3. Create a migration if needed: `mix ecto.gen.migration feature_name`
4. Update LiveView components in `lib/slap_web/live/`
5. Add tests for your new functionality
6. Run tests: `mix test`
7. Format code: `mix format`

### Debugging

#### Console Logging

Add debug output to your LiveView or context:

```elixir
# In LiveView
IO.inspect(socket.assigns, label: "Socket assigns")

# In context
IO.inspect(params, label: "Function parameters")
```

#### Breakpoints

Use `IEx.pry/0` to set breakpoints:

```elixir
def some_function(param) do
  require IEx; IEx.pry()
  # Code execution will pause here
  # You can inspect variables and execute code
  result = do_something(param)
  result
end
```

#### Database Query Debugging

Enable query logging in `config/dev.exs`:

```elixir
config :slap, Slap.Repo,
  # ... other config
  log: :debug
```

### Performance Testing

Load test your application with tools like:
- [k6](https://k6.io/)
- [Apache Bench (ab)](https://httpd.apache.org/docs/2.4/programs/ab.html)
- [ wrk](https://github.com/wg/wrk)

Example with Apache Bench:
```bash
ab -n 1000 -c 10 http://localhost:4000/
```

## Troubleshooting

### Common Issues

#### Database Connection Errors

**Error**: `Postgrex.Protocol` connection refused

**Solution**:
1. Ensure PostgreSQL is running
2. Check database credentials in `config/dev.exs`
3. Verify database exists: `createdb slap_dev`

#### Port Already in Use

**Error**: Port 4000 is already in use

**Solution**:
1. Find the process using the port: `lsof -i :4000`
2. Kill the process: `kill -9 <PID>`
3. Or use a different port: `PORT=4001 mix phx.server`

#### Asset Build Issues

**Error**: npm or esbuild errors

**Solution**:
1. Clear npm cache: `npm cache clean --force`
2. Delete node_modules: `rm -rf assets/node_modules`
3. Reinstall dependencies: `cd assets && npm install`

#### Compilation Errors

**Error**: Compilation failed

**Solution**:
1. Check for syntax errors in the indicated file
2. Ensure all dependencies are installed: `mix deps.get`
3. Clean and recompile: `mix clean && mix compile`

### Getting Help

1. Check the [Phoenix documentation](https://hexdocs.pm/phoenix/overview.html)
2. Search [Elixir Forum](https://elixirforum.com/)
3. Review [Phoenix LiveView docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
4. Check existing issues in the project repository

## Development Best Practices

1. **Write Tests First**: Test-driven development helps catch issues early
2. **Commit Often**: Small, focused commits are easier to review
3. **Format Code**: Use `mix format` before committing
4. **Review Changes**: Use `git diff` to review changes before committing
5. **Update Dependencies**: Regularly update dependencies with `mix deps.update`

## Next Steps

After setting up your development environment:

1. Read the [Architecture Overview](./architecture.md) to understand the application structure
2. Explore the [Features Documentation](./features.md) to learn about specific functionality
3. Check the [API Documentation](./api.md) for technical reference
4. Review the [Testing Guidelines](./testing.md) to understand the testing approach

Happy coding! 🚀