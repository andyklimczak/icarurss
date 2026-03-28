defmodule Icarurss.Workers.RefreshAllFeedsWorker do
  @moduledoc """
  Refreshes all subscribed feeds.
  """

  use Oban.Worker,
    queue: :feed_refresh,
    max_attempts: 3,
    unique: [period: 30, fields: [:worker]]

  alias Ecto.Multi
  alias Icarurss.{Reader, Repo}
  alias Icarurss.Workers.RefreshFeedWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    max_count =
      case Map.get(args, "max_count") do
        value when is_integer(value) and value > 0 -> value
        _ -> 5_000
      end

    if spread_refreshes?(args) do
      schedule_feed_refreshes(max_count)
    else
      refresh_all_feeds_now(max_count)
    end
  end

  defp refresh_all_feeds_now(max_count) do
    max_concurrency =
      Application.get_env(:icarurss, :feed_refresh, [])
      |> Keyword.get(:max_concurrency, 1)

    _stats = Reader.refresh_all_feeds(limit: max_count, max_concurrency: max_concurrency)

    :ok
  end

  defp schedule_feed_refreshes(max_count) do
    feed_ids = Reader.list_all_feed_ids(limit: max_count)

    case feed_ids do
      [] ->
        :ok

      _ ->
        spread_window_seconds =
          Application.get_env(:icarurss, :feed_refresh, [])
          |> Keyword.get(:spread_window_seconds, 600)

        multi =
          feed_ids
          |> Enum.with_index()
          |> Enum.reduce(Multi.new(), fn {feed_id, index}, multi ->
            schedule_in = stagger_seconds(index, length(feed_ids), spread_window_seconds)

            changeset =
              RefreshFeedWorker.new(%{feed_id: feed_id}, schedule_in: schedule_in)

            Oban.insert(multi, {:refresh_feed, feed_id}, changeset)
          end)

        case Repo.transaction(multi) do
          {:ok, _result} -> :ok
          {:error, _operation, reason, _changes_so_far} -> {:error, reason}
        end
    end
  end

  defp spread_refreshes?(args) when is_map(args) do
    Map.get(args, "spread", true)
  end

  defp stagger_seconds(_index, _count, spread_window_seconds) when spread_window_seconds <= 0,
    do: 0

  defp stagger_seconds(_index, count, _spread_window_seconds) when count <= 1, do: 0

  defp stagger_seconds(index, count, spread_window_seconds) do
    div(index * spread_window_seconds, count)
  end
end
