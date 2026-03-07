import Config

env_truthy? = fn
  nil -> false
  value -> String.downcase(value) in ["1", "true", "yes", "on"]
end

positive_integer_env = fn key, default ->
  case System.get_env(key) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {parsed, ""} when parsed > 0 -> parsed
        _ -> default
      end
  end
end

non_negative_integer_env = fn key, default ->
  case System.get_env(key) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {parsed, ""} when parsed >= 0 -> parsed
        _ -> default
      end
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/icarurss start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER")
   |> env_truthy?.() do
  config :icarurss, IcarurssWeb.Endpoint, server: true
end

config :icarurss, IcarurssWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

registration_enabled =
  System.get_env("REGISTRATION_ENABLED", "false")
  |> env_truthy?.()

config :icarurss, registration_enabled: registration_enabled

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/icarurss/data/icarurss_prod.db
      """

  sqlite_busy_timeout = positive_integer_env.("SQLITE_BUSY_TIMEOUT_MS", 5_000)
  pool_size = positive_integer_env.("POOL_SIZE", 5)
  feed_refresh_concurrency = positive_integer_env.("FEED_REFRESH_CONCURRENCY", 1)
  feed_refresh_max_concurrency = positive_integer_env.("FEED_REFRESH_MAX_CONCURRENCY", 1)
  feed_fetch_connect_timeout = positive_integer_env.("FEED_FETCH_CONNECT_TIMEOUT_MS", 5_000)
  feed_fetch_pool_timeout = positive_integer_env.("FEED_FETCH_POOL_TIMEOUT_MS", 5_000)
  feed_fetch_receive_timeout = positive_integer_env.("FEED_FETCH_RECEIVE_TIMEOUT_MS", 10_000)
  feed_fetch_max_retries = non_negative_integer_env.("FEED_FETCH_MAX_RETRIES", 0)

  config :icarurss, Icarurss.Repo,
    database: database_path,
    busy_timeout: sqlite_busy_timeout,
    pool_size: pool_size

  config :icarurss, :feed_fetch,
    connect_timeout: feed_fetch_connect_timeout,
    max_retries: feed_fetch_max_retries,
    pool_timeout: feed_fetch_pool_timeout,
    receive_timeout: feed_fetch_receive_timeout,
    retry: feed_fetch_max_retries > 0

  config :icarurss, :feed_refresh, max_concurrency: feed_refresh_max_concurrency

  config :icarurss, Oban, queues: [feed_refresh: feed_refresh_concurrency]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  force_ssl? =
    System.get_env("FORCE_SSL", "false")
    |> env_truthy?.()

  scheme = System.get_env("PHX_SCHEME") || if(force_ssl?, do: "https", else: "http")
  host = System.get_env("PHX_HOST") || "localhost"

  url_port =
    System.get_env("PHX_URL_PORT") ||
      if(force_ssl?, do: "443", else: System.get_env("PORT", "4000"))

  config :icarurss, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :icarurss, IcarurssWeb.Endpoint,
    url: [host: host, port: String.to_integer(url_port), scheme: scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    force_ssl:
      if(force_ssl?,
        do: [rewrite_on: [:x_forwarded_proto], exclude: [hosts: ["localhost", "127.0.0.1"]]],
        else: false
      ),
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :icarurss, IcarurssWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :icarurss, IcarurssWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :icarurss, Icarurss.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
