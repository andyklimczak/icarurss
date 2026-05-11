defmodule Icarurss.Reader.FeedSource.Fake do
  @behaviour Icarurss.Reader.FeedSource

  @impl true
  def discover(url) do
    case Application.get_env(:icarurss, :feed_source_fake_discover) do
      function when is_function(function, 1) -> function.(url)
      {:ok, _candidates} = ok -> ok
      {:error, _reason} = error -> error
      _ -> {:error, "No fake discover response configured"}
    end
  end

  @impl true
  def fetch_feed(feed_url) do
    case Application.get_env(:icarurss, :feed_source_fake_fetch_feed) do
      function when is_function(function, 1) -> function.(feed_url)
      {:ok, _payload} = ok -> ok
      {:error, _reason} = error -> error
      _ -> {:error, "No fake fetch response configured"}
    end
  end

  @impl true
  def fetch_feed(feed_url, opts) do
    with {:ok, payload} <- fetch_feed(feed_url) do
      callback = Keyword.get(opts, :on_entry)
      initial_acc = Keyword.get(opts, :entry_acc)
      entries = Map.get(payload, :entries, [])

      acc =
        if is_function(callback, 2) do
          Enum.reduce(entries, initial_acc, fn entry, acc -> callback.(entry, acc) end)
        else
          initial_acc
        end

      {:ok, %{payload | entries: []}, acc,
       %{http_status: nil, bytes: nil, parsed_items: length(entries), duration_ms: nil}}
    else
      {:error, reason} -> {:error, reason, %{}}
    end
  end
end
