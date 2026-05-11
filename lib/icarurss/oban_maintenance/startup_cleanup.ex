defmodule Icarurss.ObanMaintenance.StartupCleanup do
  @moduledoc false

  require Logger

  alias Icarurss.ObanMaintenance

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [fn -> run(opts) end]},
      restart: :transient
    }
  end

  defp run(_opts) do
    if oban_enabled?() do
      _ = ObanMaintenance.cleanup_stale_feed_jobs()
    else
      Logger.debug("Skipping stale feed job cleanup because Oban queues are disabled")
    end
  end

  defp oban_enabled? do
    oban_config = Application.get_env(:icarurss, Oban, [])
    Keyword.get(oban_config, :queues) != false
  end
end
