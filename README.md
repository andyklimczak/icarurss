# Icarurss

Icarurss is a self-hosted RSS reader built with Phoenix and SQLite.

## What It Is

- Phoenix LiveView web app for reading RSS feeds
- SQLite-backed, with data stored in a local volume
- Designed to run locally for development or as a small self-hosted service

## Self-Hosted Setup

The simplest deployment path is Docker Compose from a Git checkout.

### Requirements

- Docker
- Docker Compose
- A host with persistent storage for `./data`

### 1. Clone and prepare the app

```bash
git clone <your-github-url> icarurss
cd icarurss
cp .env.example .env
mkdir -p data
```

### 2. Configure `.env`

Set `SECRET_KEY_BASE` to a long random value:

```bash
openssl rand -base64 48
```

The defaults in `.env.example` are enough to start locally. For a real deployment, update these as needed:

- `PHX_HOST` to your domain or server hostname
- `PHX_SCHEME=https` and `PHX_URL_PORT=443` if you are running behind HTTPS
- `FORCE_SSL=true` if TLS is terminated in front of the app
- `REGISTRATION_ENABLED=false` if you do not want open signups

### 3. Start the service

```bash
docker compose up -d --build
docker compose logs -f app
```

The image build installs dependencies, compiles the app, and builds assets. Container startup only
creates the data directory, runs release-time migrations, and starts Phoenix.

### 4. Create the first user

The Docker image now runs as a Phoenix release, so Mix tasks are not available inside the running
container. For the first user, temporarily set this in `.env`:

```text
REGISTRATION_ENABLED=true
```

Restart the service, open `http://localhost:4000/users/register`, and create the account:

```bash
docker compose up -d
```

For a public deployment, set `REGISTRATION_ENABLED=false` in `.env` after the first account is
created, then run `docker compose up -d` again.

### 5. Update later

```bash
docker compose down
git pull
docker compose up -d --build
```

The SQLite database lives under `./data`.

### Maintenance Commands

Because the production container is a release image, run Mix maintenance tasks from a local checkout
with Elixir installed, pointed at the Compose database:

```bash
set -a
. ./.env
set +a
DATABASE_PATH="$PWD/data/icarurss_prod.db" MIX_ENV=prod mix users.reset_password <username>
DATABASE_PATH="$PWD/data/icarurss_prod.db" MIX_ENV=prod mix icarurss.oban.cleanup_stale_feed_jobs
```

The app also runs scoped stale feed-job cleanup automatically at startup.

### Feed refresh and Oban settings

The Compose file exposes conservative defaults for small hosts:

- `MAX_FEED_BYTES=25000000` (`0` disables the response byte limit)
- `MAX_ITEMS_PER_FEED=500`
- `FEED_FETCH_RECEIVE_TIMEOUT_MS=30000`
- `OBAN_PRUNE_MAX_AGE_SECONDS=21600`
- `OBAN_PRUNE_LIMIT=500`
- `SQLITE_BUSY_TIMEOUT_MS=15000`
- `STALE_FEED_JOB_TIMEOUT_SECONDS=3600`

## Local Development

### Requirements

- Elixir and Erlang
- SQLite3
- `mise` if you want to use the included toolchain file

### Setup

```bash
mise install
mise exec -- mix setup
mise exec -- mix phx.server
```

Useful local commands:

```bash
mise exec -- mix users.new
mise exec -- mix users.reset_password <username>
```

Open `http://localhost:4000`.
