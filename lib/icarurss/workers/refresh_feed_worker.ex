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
  def backoff(%Oban.Job{attempt: attempt}) do
    min(300, attempt * attempt * 30)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"feed_id" => feed_id}}) when is_integer(feed_id) do
    case Reader.get_feed(feed_id) do
      nil ->
        :ok

      feed ->
        case Reader.refresh_feed(feed) do
          {:ok, _stats} ->
            :ok

          {:error, reason} ->
            if Reader.refresh_error_retryable?(reason) do
              {:error, reason}
            else
              {:cancel, reason}
            end
        end
    end
  end

  def perform(%Oban.Job{}), do: :ok
end
