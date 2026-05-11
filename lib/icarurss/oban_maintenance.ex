defmodule Icarurss.ObanMaintenance do
  @moduledoc """
  Operational maintenance helpers for Oban jobs owned by this application.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Oban.{Engine, Job}

  @feed_workers [
    "Icarurss.Workers.RefreshFeedWorker",
    "Icarurss.Workers.RefreshAllFeedsWorker"
  ]

  def cleanup_stale_feed_jobs(opts \\ []) do
    timeout_seconds =
      Keyword.get_lazy(opts, :timeout_seconds, fn ->
        Application.get_env(:icarurss, :oban_maintenance, [])
        |> Keyword.get(:stale_feed_job_timeout_seconds, 60 * 60)
      end)

    conf = Keyword.get_lazy(opts, :conf, fn -> Oban.config() end)
    rescue_after = :timer.seconds(timeout_seconds)

    query =
      from job in Job,
        where: job.worker in ^@feed_workers and job.state == "executing"

    case Engine.rescue_jobs(conf, query, rescue_after: rescue_after) do
      {:ok, jobs} ->
        rescued = Enum.count(jobs, &(&1.state == "available"))
        discarded = Enum.count(jobs, &(&1.state == "discarded"))

        Logger.info(
          "Cleaned stale feed refresh jobs rescued=#{rescued} discarded=#{discarded} timeout_seconds=#{timeout_seconds}"
        )

        {:ok, %{rescued: rescued, discarded: discarded, total: length(jobs)}}

      {:error, reason} ->
        Logger.warning("Could not clean stale feed refresh jobs: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
