defmodule Icarurss.Workers.RefreshFeedWorker do
  @moduledoc """
  Refreshes a single feed and retries on transient failures.
  """

  use Oban.Worker,
    queue: :feed_refresh,
    max_attempts: 5,
    unique: [period: 60, fields: [:worker, :args], keys: [:feed_id]]

  alias Icarurss.Reader

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"feed_id" => feed_id}}) when is_integer(feed_id) do
    case Reader.get_feed(feed_id) do
      nil ->
        :ok

      feed ->
        case Reader.refresh_feed(feed) do
          {:ok, _stats} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def perform(%Oban.Job{}), do: :ok
end
