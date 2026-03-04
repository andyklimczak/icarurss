#!/usr/bin/env sh
set -eu

cd /app

MIX_ENV="${MIX_ENV:-prod}"
export MIX_ENV
export PHX_SERVER="${PHX_SERVER:-true}"

if [ -n "${DATABASE_PATH:-}" ]; then
  mkdir -p "$(dirname "$DATABASE_PATH")"
fi

mix deps.get --only "$MIX_ENV"
mix deps.compile
mix compile
mix assets.deploy
mix ecto.migrate

exec mix phx.server
