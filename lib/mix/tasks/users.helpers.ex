defmodule Mix.Tasks.Users.Helpers do
  @moduledoc false

  def disable_endpoint_server do
    endpoint_config = Application.get_env(:icarurss, IcarurssWeb.Endpoint, [])

    Application.put_env(
      :icarurss,
      IcarurssWeb.Endpoint,
      Keyword.put(endpoint_config, :server, false)
    )
  end
end
