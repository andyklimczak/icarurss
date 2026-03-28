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
docker compose up -d
docker compose logs -f app
```

On startup the container installs dependencies, compiles the app, builds assets, and runs migrations automatically.

### 4. Create the first user

```bash
docker compose exec app mix users.new
```

If the container is not already running:

```bash
docker compose run --rm app mix users.new
```

To reset a password later:

```bash
docker compose exec app mix users.reset_password <username>
```

### 5. Update later

```bash
docker compose down
git pull
docker compose up -d
```

The SQLite database lives under `./data`.

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
