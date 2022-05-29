defmodule Icarurss.Repo do
  use Ecto.Repo,
    otp_app: :icarurss,
    adapter: Ecto.Adapters.Postgres
end
