defmodule Icarurss.Repo do
  use Ecto.Repo,
    otp_app: :icarurss,
    adapter: Ecto.Adapters.SQLite3
end
