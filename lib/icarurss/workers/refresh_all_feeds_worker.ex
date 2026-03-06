defmodule Icarurss.Workers.RefreshAllFeedsWorker do
  @moduledoc """
  Refreshes all subscribed feeds.
  """

  use Oban.Worker,
    queue: :feed_refresh,
    max_attempts: 3,
    unique: [period: 30, fields: [:worker]]

  alias Icarurss.Reader
  alias Icarurss.Workers.RefreshFeedWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    max_count =
      case Map.get(args, "max_count") do
        value when is_integer(value) and value > 0 -> value
        _ -> 5_000
      end

    spacing_ms =
      Application.get_env(:icarurss, :feed_refresh, [])
      |> Keyword.get(:spacing_ms, 1_000)

    scheduled_at = DateTime.utc_now()

    Reader.list_all_feed_ids(limit: max_count)
    |> Enum.with_index()
    |> Enum.map(fn {feed_id, index} ->
      %{feed_id: feed_id}
      |> RefreshFeedWorker.new(
        scheduled_at: DateTime.add(scheduled_at, index * spacing_ms, :millisecond)
      )
    end)
    |> Oban.insert_all()

    :ok
  end
end
