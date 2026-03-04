defmodule Icarurss.Reader.FeedDiscovery do
  @moduledoc """
  Extracts candidate feed URLs from an HTML page.
  """

  @link_regex ~r/<link\b[^>]*>/i
  @attr_regex ~r/([a-zA-Z_:][\w:.-]*)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i
  @feed_type_regex ~r/(rss|atom|xml)/i

  @spec discover_from_html(String.t(), String.t()) :: [map()]
  def discover_from_html(html, page_url) when is_binary(html) and is_binary(page_url) do
    html
    |> extract_link_tags()
    |> Enum.map(&parse_link_attributes/1)
    |> Enum.filter(&feed_link?/1)
    |> Enum.map(&candidate_from_attrs(&1, page_url))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.feed_url)
  end

  @spec candidate_from_feed_payload(String.t(), map()) :: map()
  def candidate_from_feed_payload(feed_url, payload)
      when is_binary(feed_url) and is_map(payload) do
    %{
      feed_url: feed_url,
      title: payload[:title],
      site_url: payload[:site_url],
      base_url: payload[:base_url],
      favicon_url: payload[:favicon_url]
    }
  end

  defp extract_link_tags(html) do
    Regex.scan(@link_regex, html)
    |> Enum.map(fn [tag] -> tag end)
  end

  defp parse_link_attributes(link_tag) do
    Regex.scan(@attr_regex, link_tag)
    |> Enum.reduce(%{}, fn [_, key, raw_value], acc ->
      value = raw_value |> String.trim_leading("\"") |> String.trim_trailing("\"")
      value = value |> String.trim_leading("'") |> String.trim_trailing("'")
      Map.put(acc, String.downcase(key), html_unescape(String.trim(value)))
    end)
  end

  defp feed_link?(attrs) do
    rel = Map.get(attrs, "rel", "") |> String.downcase()
    type = Map.get(attrs, "type", "") |> String.downcase()
    href = Map.get(attrs, "href", "")

    href != "" and String.contains?(rel, "alternate") and Regex.match?(@feed_type_regex, type)
  end

  defp candidate_from_attrs(attrs, page_url) do
    href = Map.get(attrs, "href", "")
    title = attrs |> Map.get("title") |> blank_to_nil()
    resolved_feed_url = resolve_url(href, page_url)

    if resolved_feed_url do
      site_url = page_url |> normalize_url() |> origin_url()

      %{
        feed_url: resolved_feed_url,
        title: title,
        site_url: site_url,
        base_url: site_url,
        favicon_url: favicon_url_for(site_url)
      }
    end
  end

  defp resolve_url("", _page_url), do: nil

  defp resolve_url(url, page_url) do
    uri = URI.parse(url)

    cond do
      uri.scheme in ["http", "https"] ->
        URI.to_string(uri)

      is_binary(uri.host) and uri.host != "" ->
        URI.to_string(%URI{uri | scheme: uri.scheme || "https"})

      true ->
        page_uri = URI.parse(page_url)

        case URI.merge(page_uri, url) do
          %URI{scheme: scheme} = merged when scheme in ["http", "https"] -> URI.to_string(merged)
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp normalize_url(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] do
      URI.to_string(uri)
    else
      "https://" <> String.trim_leading(url, "/")
    end
  end

  defp origin_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        "#{scheme}://#{host}"

      _ ->
        nil
    end
  end

  defp favicon_url_for(nil), do: nil
  defp favicon_url_for(origin), do: origin <> "/favicon.ico"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp html_unescape(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end
end
