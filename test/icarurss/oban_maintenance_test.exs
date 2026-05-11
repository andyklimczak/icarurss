defmodule Icarurss.ObanMaintenanceTest do
  use Icarurss.DataCase, async: false

  alias Icarurss.ObanMaintenance
  alias Icarurss.Repo

  test "rescues only stale executing feed refresh jobs" do
    stale_feed_job =
      insert_oban_job(
        worker: "Icarurss.Workers.RefreshFeedWorker",
        state: "executing",
        attempted_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :hour)
      )

    fresh_feed_job =
      insert_oban_job(
        worker: "Icarurss.Workers.RefreshFeedWorker",
        state: "executing",
        attempted_at: DateTime.utc_now(:microsecond)
      )

    other_job =
      insert_oban_job(
        worker: "Icarurss.Workers.OtherWorker",
        state: "executing",
        attempted_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :hour)
      )

    assert {:ok, %{rescued: 1, discarded: 0, total: 1}} =
             ObanMaintenance.cleanup_stale_feed_jobs(timeout_seconds: 3_600)

    assert Repo.reload!(stale_feed_job).state == "available"
    assert Repo.reload!(fresh_feed_job).state == "executing"
    assert Repo.reload!(other_job).state == "executing"
  end

  test "discards stale feed jobs that exhausted attempts" do
    stale_feed_job =
      insert_oban_job(
        worker: "Icarurss.Workers.RefreshFeedWorker",
        state: "executing",
        attempt: 5,
        max_attempts: 5,
        attempted_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :hour)
      )

    assert {:ok, %{rescued: 0, discarded: 1, total: 1}} =
             ObanMaintenance.cleanup_stale_feed_jobs(timeout_seconds: 3_600)

    assert Repo.reload!(stale_feed_job).state == "discarded"
  end

  test "is idempotent" do
    insert_oban_job(
      worker: "Icarurss.Workers.RefreshAllFeedsWorker",
      state: "executing",
      attempted_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :hour)
    )

    assert {:ok, %{total: 1}} = ObanMaintenance.cleanup_stale_feed_jobs(timeout_seconds: 3_600)
    assert {:ok, %{total: 0}} = ObanMaintenance.cleanup_stale_feed_jobs(timeout_seconds: 3_600)
  end

  defp insert_oban_job(attrs) do
    now = DateTime.utc_now(:microsecond)

    attrs =
      %{
        worker: "Icarurss.Workers.RefreshFeedWorker",
        args: %{},
        meta: %{},
        tags: [],
        errors: [],
        queue: "feed_refresh",
        state: "executing",
        attempt: 1,
        max_attempts: 5,
        priority: 0,
        attempted_by: [],
        attempted_at: now,
        inserted_at: now,
        scheduled_at: now
      }
      |> Map.merge(Map.new(attrs))

    %Oban.Job{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end
