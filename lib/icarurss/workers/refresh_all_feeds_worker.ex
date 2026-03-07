defmodule Icarurss.Workers.RefreshAllFeedsWorker do
  @moduledoc """
  Refreshes all subscribed feeds.
  """

  use Oban.Worker,
    queue: :feed_refresh,
    max_attempts: 3,
    unique: [period: 30, fields: [:worker]]

  alias Icarurss.Reader

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    max_count =
      case Map.get(args, "max_count") do
        value when is_integer(value) and value > 0 -> value
        _ -> 5_000
      end

    max_concurrency =
      Application.get_env(:icarurss, :feed_refresh, [])
      |> Keyword.get(:max_concurrency, 1)

    _stats = Reader.refresh_all_feeds(limit: max_count, max_concurrency: max_concurrency)

    :ok
  end
end
