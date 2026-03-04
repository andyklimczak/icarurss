FROM elixir:1.19.5-otp-28

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git sqlite3 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/data/icarurss_prod.db

EXPOSE 4000
