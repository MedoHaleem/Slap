# Deployment

This document provides a comprehensive overview of deployment options and configurations for the Slap application.

## Table of Contents

1. [Production Configuration](./deployment/production-config.md)
2. [Deployment Options](./deployment/deployment-options.md)
3. [Monitoring](./deployment/monitoring.md)

## Overview

The Slap application can be deployed in various environments, from development to production. This guide covers:

- Production configuration
- Deployment strategies
- Environment-specific settings
- Monitoring and observability
- Security considerations

## Deployment Architecture

### Application Components

A typical production deployment includes:

- **Phoenix Application**: The main web server
- **Database**: PostgreSQL instance
- **File Storage**: Local or cloud storage for uploads
- **Load Balancer**: (Optional) For high availability
- **CDN**: (Optional) For static asset delivery

### Deployment Flow

```mermaid
graph LR
    A[Developer] --> B[Git Repository]
    B --> C[CI/CD Pipeline]
    C --> D[Build Assets]
    D --> E[Compile Release]
    E --> F[Deploy to Server]
    F --> G[Run Migrations]
    G --> H[Start Application]
```

## Environment Configuration

### Environment Variables

The application uses environment variables for configuration:

```bash
# Database
DATABASE_URL=postgresql://user:password@host:port/database
POOL_SIZE=10

# Secret Key Base
SECRET_KEY_BASE=your_secret_key_base

# LiveView
LIVE_VIEW_SIGNING_SALT=your_signing_salt

# Host and Port
HOST=yourdomain.com
PORT=4000

# SSL
SSL_KEY_PATH=/path/to/ssl/key
SSL_CERT_PATH=/path/to/ssl/cert

# File Uploads
UPLOAD_PATH=/var/www/uploads
MAX_FILE_SIZE=10485760  # 10MB

# Email (if using)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your_email@example.com
SMTP_PASSWORD=your_password
```

### Runtime Configuration

Runtime configuration is handled in `config/runtime.exs`:

```elixir
import Config

# Configure database
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      """

  config :slap, Slap.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      """

  config :slap, SlapWeb.Endpoint,
    url: [host: System.get_env("HOST"), port: 4000],
    cache_static_manifest: "priv/static/cache_manifest.json",
    server: true,
    secret_key_base: secret_key_base

  # Configure SSL
  if System.get_env("SSL_KEY_PATH") && System.get_env("SSL_CERT_PATH") do
    config :slap, SlapWeb.Endpoint,
      https: [
        port: 443,
        cipher_suite: :strong,
        keyfile: System.get_env("SSL_KEY_PATH"),
        certfile: System.get_env("SSL_CERT_PATH")
      ]
  end
end
```

## Build Process

### Release Build

Create a production release:

```bash
# Build the release
mix release

# Or with environment
MIX_ENV=prod mix release
```

### Asset Compilation

Compile and digest assets:

```bash
# Build assets for production
mix assets.deploy

# Or manually
cd assets
npm run build
cd ..
mix phx.digest
```

### Database Setup

Set up the production database:

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Load seed data (optional)
mix run priv/repo/seeds.exs
```

## Deployment Strategies

### Traditional Server Deployment

Deploy to a single server:

```bash
# 1. Clone repository
git clone https://github.com/your-org/slap.git
cd slap

# 2. Install dependencies
mix deps.get --only prod
cd assets && npm ci && cd ..

# 3. Compile and build
MIX_ENV=prod mix compile
mix assets.deploy

# 4. Create release
MIX_ENV=prod mix release

# 5. Setup database
mix ecto.create
mix ecto.migrate

# 6. Start application
./_build/prod/rel/slap/bin/slap start
```

### Systemd Service

Create a systemd service for automatic management:

```ini
# /etc/systemd/system/slap.service
[Unit]
Description=Slap Application
After=network.target

[Service]
Type=simple
User=slap
Group=slap
WorkingDirectory=/var/www/slap
ExecStart=/var/www/slap/_build/prod/rel/slap/bin/slap start
ExecStop=/var/www/slap/_build/prod/rel/slap/bin/slap stop
Restart=on-failure
Environment=LANG=en_US.UTF-8
Environment=LC_ALL=en_US.UTF-8
Environment=MIX_ENV=prod

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl enable slap
sudo systemctl start slap
sudo systemctl status slap
```

### Docker Deployment

#### Dockerfile

```dockerfile
# Dockerfile
FROM elixir:1.14-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base npm git python3

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
RUN mkdir config
COPY .env.prod config/.env

# Compile assets
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm --prefix ./assets ci
COPY priv priv
COPY assets assets
RUN npm run --prefix ./assets deploy
RUN mix phx.digest

# Compile the application
COPY lib lib
RUN mix compile

# Build a release
COPY config/runtime.exs config/
RUN mix release

# Prepare a minimal image for the release
FROM alpine:3.16 AS app

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=builder /app/_build/prod/rel/slap ./

ENV HOME=/app

CMD ["bin/slap", "start"]
```

#### Docker Compose

```yaml
# docker-compose.yml
version: "3.9"

services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/slap_prod
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - HOST=localhost
    depends_on:
      - db
    volumes:
      - ./uploads:/app/uploads

  db:
    image: postgres:13
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=slap_prod
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

### Cloud Deployment

#### Fly.io

Deploy to Fly.io:

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Launch app
fly launch

# Set secrets
fly secrets set DATABASE_URL=postgresql://...
fly secrets set SECRET_KEY_BASE=...

# Deploy
fly deploy
```

#### Render

Deploy to Render:

1. Connect your GitHub repository
2. Configure build command: `mix setup && mix assets.deploy`
3. Configure start command: `_build/prod/rel/slap/bin/slap start`
4. Add environment variables
5. Deploy

#### Gigalixir

Deploy to Gigalixir:

```bash
# Install gigalixir CLI
mix archive.install hex gigalixir

# Login
gigalixir login

# Create app
gigalixir create

# Set environment variables
gigalixir config:set DATABASE_URL=...
gigalixir config:set SECRET_KEY_BASE=...

# Deploy
gigalixir deploy
```

## Database Management

### Production Database

Configure PostgreSQL for production:

```sql
-- Create database user
CREATE USER slap_prod WITH PASSWORD 'secure_password';

-- Create database
CREATE DATABASE slap_prod OWNER slap_prod;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE slap_prod TO slap_prod;
```

### Connection Pooling

Configure connection pooling:

```elixir
# config/prod.exs
config :slap, Slap.Repo,
  pool_size: 20,
  queue_target: 5000,
  queue_interval: 1000
```

### Database Backups

Set up automated backups:

```bash
# Daily backup script
#!/bin/bash
BACKUP_DIR="/var/backups/slap"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="slap_prod"

# Create backup
pg_dump -h localhost -U slap_prod $DB_NAME > $BACKUP_DIR/backup_$DATE.sql

# Compress old backups
find $BACKUP_DIR -name "backup_*.sql" -mtime +7 -exec gzip {} \;

# Remove old backups
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +30 -delete
```

## File Storage

### Local Storage

Configure local file storage:

```elixir
# config/prod.exs
config :slap, :uploads,
  path: System.get_env("UPLOAD_PATH") || "/var/www/uploads",
  max_size: 10_485_760  # 10MB
```

### Cloud Storage (Future)

Configure cloud storage (e.g., AWS S3):

```elixir
# config/prod.exs
config :slap, :uploads,
  storage: :s3,
  bucket: System.get_env("S3_BUCKET"),
  region: System.get_env("AWS_REGION"),
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

## SSL/TLS Configuration

### Let's Encrypt

Set up automatic SSL with Let's Encrypt:

```bash
# Install certbot
sudo apt-get install certbot

# Generate certificate
sudo certbot certonly --standalone -d yourdomain.com

# Configure renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

### SSL Configuration

Configure SSL in Phoenix:

```elixir
# config/prod.exs
config :slap, SlapWeb.Endpoint,
  https: [
    port: 443,
    cipher_suite: :strong,
    keyfile: System.get_env("SSL_KEY_PATH"),
    certfile: System.get_env("SSL_CERT_PATH"),
    transport_options: [socket_opts: [:inet6]]
  ]
```

## Monitoring and Logging

### Application Logging

Configure logging for production:

```elixir
# config/prod.exs
config :logger, level: :info

# Custom logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

### Health Checks

Implement health check endpoints:

```elixir
# lib/slap_web/health_check.ex
defmodule SlapWeb.HealthCheck do
  use SlapWeb, :controller

  def health(conn, _params) do
    # Check database connection
    db_status = case Slap.Repo.query("SELECT 1") do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end

    json(conn, %{
      status: "ok",
      database: db_status,
      timestamp: DateTime.utc_now()
    })
  end
end
```

### Metrics Collection

Configure telemetry and metrics:

```elixir
# lib/slap/telemetry.ex
defmodule Slap.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      counter("slap.web.requests.total"),
      sum("slap.web.request.duration"),
      last_value("slap.web.user.count")
    ]
  end

  defp periodic_measurements do
    [
      # A periodic measurement
      {
        :slap,
        :user_count,
        %{},
        fn -> {:ok, Slap.Accounts.count_users()} end
      }
    ]
  end
end
```

## Security Considerations

### Environment Variables

Secure sensitive configuration:

```bash
# Use environment variables for secrets
export DATABASE_URL="postgresql://..."
export SECRET_KEY_BASE="$(openssl rand -base64 48)"

# Use .env files for development
# Never commit .env files to version control
echo ".env" >> .gitignore
```

### Firewall Configuration

Configure firewall rules:

```bash
# Allow HTTP and HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Allow SSH (adjust port as needed)
sudo ufw allow 22

# Enable firewall
sudo ufw enable
```

### Security Headers

Add security headers:

```elixir
# lib/slap_web/plugs/security.ex
defmodule SlapWeb.Plugs.Security do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("strict-transport-security", "max-age=31536000; includeSubDomains")
  end
end
```

## Performance Optimization

### Release Optimization

Optimize the release for production:

```elixir
# mix.exs
def release do
  [
    applications: [runtime_tools: :permanent],
    strip_beams: [keep: ["Docs"]],
    steps: [:assemble, :tar]
  ]
end
```

### Asset Optimization

Optimize assets for production:

```javascript
// assets/build.js
esbuild.build({
  minify: true,
  sourcemap: false,
  target: "es2017",
  // ... other options
});
```

### Database Optimization

Optimize database for production:

```sql
-- Add indexes for common queries
CREATE INDEX CONCURRENTLY idx_messages_room_id_created_at 
ON messages(room_id, inserted_at DESC);

-- Analyze tables for query planner
ANALYZE messages;
ANALYZE users;
ANALYZE rooms;
```

## Troubleshooting

### Common Issues

#### Application Won't Start

Check logs for errors:

```bash
# View application logs
./_build/prod/rel/slap/bin/slap foreground

# Check system logs
sudo journalctl -u slap -f
```

#### Database Connection Issues

Verify database configuration:

```bash
# Test database connection
psql -h localhost -U slap_prod -d slap_prod

# Check connection limits
SELECT * FROM pg_stat_activity WHERE datname = 'slap_prod';
```

#### SSL Certificate Issues

Verify SSL configuration:

```bash
# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/yourdomain.com/cert.pem -text -noout

# Test SSL configuration
openssl s_client -connect yourdomain.com:443
```

### Performance Issues

Monitor application performance:

```bash
# Check system resources
top
htop
free -h
df -h

# Monitor database queries
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;
```

This deployment documentation provides a comprehensive guide for deploying the Slap application to production environments with proper configuration, security, and monitoring.