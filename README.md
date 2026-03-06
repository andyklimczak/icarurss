# Icarurss

Icarurss is a Phoenix + SQLite RSS reader.

## Development

### Prerequisites

- Elixir/Erlang (repo includes `.mise.toml`)
- SQLite3

### Setup

1. Install toolchain (if using mise):
   - `mise install`
2. Install deps and initialize DB:
   - `mise exec -- mix setup`
3. Run server:
   - `mise exec -- mix phx.server`
4. Open:
   - `http://localhost:4000`

### Useful dev commands

- Create/update user:
  - `mise exec -- mix users.new`
  - `mise exec -- mix users.new --as admin_username`
- Run tests:
  - `mise exec -- mix test`
- Run full checks:
  - `mise exec -- mix precommit`

### Local data paths

- Development DB: `data/icarurss_dev.db`
- Test DB: `data/icarurss_test.db`

## Self-host on Proxmox VM (Git pull workflow)

This deployment runs your checked-out source code inside Docker.  
Upgrade flow:

```bash
docker compose down
git pull
docker compose up -d
```

No manual migration command is needed. Migrations run automatically on startup.

### 1. Create VM in Proxmox

- Ubuntu 24.04 or Debian 12
- Suggested minimum:
  - 1 vCPU
  - 1-2 GB RAM
  - 10+ GB disk

### 2. Install Docker + Compose plugin

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 3. Deploy folder and config

```bash
git clone <your-repo-url> icarurss
cd icarurss
cp .env.example .env
mkdir -p data
```

Set `.env` values:

- `SECRET_KEY_BASE` (required):
  - `openssl rand -base64 48`
- Optional:
  - `MIX_ENV=prod`
  - `PORT=4000`
  - `DATABASE_PATH=/data/icarurss_prod.db`
  - `REGISTRATION_ENABLED=false`
  - `PHX_HOST=localhost`
  - `PHX_SCHEME=http`
  - `PHX_URL_PORT=4000`
  - `FORCE_SSL=false`

For a direct LAN deployment, set `PHX_HOST` to the VM IP or hostname and leave
`PHX_SCHEME=http`, `PHX_URL_PORT=4000`, and `FORCE_SSL=false`.

For a reverse proxy / HTTPS deployment, set `PHX_HOST` to the public hostname,
`PHX_SCHEME=https`, `PHX_URL_PORT=443`, and `FORCE_SSL=true`.

### 4. First start

```bash
docker compose up -d
docker compose logs -f app
```

Open:

- `http://<vm-ip>:4000`

### 5. Create first admin user (one time)

```bash
docker compose exec app mix users.new
```

### 6. Upgrades (no tinkering)

```bash
docker compose down
git pull
docker compose up -d
```

That rebuilds runtime state from your updated repo, then applies migrations and starts the app.

### 7. Backups

```bash
cp data/icarurss_prod.db data/icarurss_prod.db.bak.$(date +%F-%H%M%S)
```

Because `./data` is bind-mounted, DB data survives container recreation.
