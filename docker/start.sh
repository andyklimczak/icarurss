#!/usr/bin/env sh
set -eu

if [ -n "${DATABASE_PATH:-}" ]; then
  mkdir -p "$(dirname "$DATABASE_PATH")"
fi

exec /app/bin/icarurss start
