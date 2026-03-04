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
end
