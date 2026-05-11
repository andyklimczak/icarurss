defmodule Mix.Tasks.Icarurss.Oban.CleanupStaleFeedJobs do
  @moduledoc """
  Rescues stale feed refresh jobs stuck in Oban's executing state.

      mix icarurss.oban.cleanup_stale_feed_jobs

  Set STALE_FEED_JOB_TIMEOUT_SECONDS to control how old an executing job must be before rescue.
  """

  use Mix.Task

  @shortdoc "Rescues stale executing feed refresh jobs"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Icarurss.ObanMaintenance.cleanup_stale_feed_jobs() do
      {:ok, %{rescued: rescued, discarded: discarded, total: total}} ->
        Mix.shell().info(
          "Cleaned stale feed refresh jobs: rescued=#{rescued} discarded=#{discarded} total=#{total}"
        )

      {:error, reason} ->
        Mix.raise("Could not clean stale feed refresh jobs: #{inspect(reason)}")
    end
  end
end
