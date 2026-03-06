defmodule Icarurss.Reader.FeedSource.ReqSource do
  @moduledoc """
  Default feed source implementation backed by Req.
  """

  @behaviour Icarurss.Reader.FeedSource

  alias Icarurss.Reader.{FeedDiscovery, FeedParser}

  @user_agent "icarurss/0.1 (+self-hosted)"

  @impl true
  def discover(url_input) when is_binary(url_input) do
    with {:ok, normalized_url} <- normalize_url(url_input),
         {:ok, response} <- fetch(normalized_url) do
      body = response.body |> to_string()

      case FeedParser.parse(body, feed_url: normalized_url) do
        {:ok, payload} ->
          {:ok, [FeedDiscovery.candidate_from_feed_payload(normalized_url, payload)]}

        {:error, _reason} ->
          candidates = FeedDiscovery.discover_from_html(body, normalized_url)

          if candidates == [] do
            {:error, "No RSS/Atom feeds found on that page"}
          else
            {:ok, candidates}
          end
      end
    end
  end

  @impl true
  def fetch_feed(feed_url) when is_binary(feed_url) do
    with {:ok, normalized_url} <- normalize_url(feed_url),
         {:ok, response} <- fetch(normalized_url),
         {:ok, payload} <- FeedParser.parse(to_string(response.body), feed_url: normalized_url) do
      {:ok, payload}
    end
  end

  defp fetch(url) do
    case Req.get(req_options(url)) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Request failed with status #{status}"}

      {:error, error} ->
        {:error, "Request error: #{Exception.message(error)}"}
    end
  end

  defp req_options(url) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])

    [
      url: url,
      headers: [{"user-agent", @user_agent}],
      connect_options: [timeout: Keyword.get(fetch_config, :connect_timeout, 5_000)],
      pool_timeout: Keyword.get(fetch_config, :pool_timeout, 5_000),
      receive_timeout: Keyword.get(fetch_config, :receive_timeout, 10_000),
      retry: Keyword.get(fetch_config, :retry, false),
      max_retries: Keyword.get(fetch_config, :max_retries, 0)
    ]
  end

  defp normalize_url(url_input) do
    trimmed = String.trim(url_input)

    cond do
      trimmed == "" ->
        {:error, "Please provide a URL"}

      true ->
        normalized =
          case URI.parse(trimmed) do
            %URI{scheme: scheme} when scheme in ["http", "https"] -> trimmed
            _ -> "https://" <> String.trim_leading(trimmed, "/")
          end

        case URI.parse(normalized) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            {:ok, URI.to_string(%URI{URI.parse(normalized) | fragment: nil})}

          _ ->
            {:error, "Please provide a valid URL"}
        end
    end
  end
end
