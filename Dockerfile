FROM elixir:1.19.5-otp-28 AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git sqlite3 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY assets assets
COPY lib lib
COPY priv priv

RUN mix compile
RUN mix assets.deploy
RUN mix release

# Erlang/OTP 28 images are based on Debian Trixie. Keep the runtime on the
# same Debian generation so the release ERTS binaries can load the required glibc.
FROM debian:trixie-slim AS runner

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates libstdc++6 openssl sqlite3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/data/icarurss_prod.db

COPY --from=builder /app/_build/prod/rel/icarurss ./
COPY docker/start.sh ./start.sh

EXPOSE 4000

CMD ["./start.sh"]
