defmodule Icarurss.Reader.FeedParser do
  @moduledoc """
  Parses RSS/Atom XML into normalized feed metadata and entries.
  """

  require Record

  Record.defrecord(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecord(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  Record.defrecord(
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def parse(xml_body, opts \\ []) when is_binary(xml_body) do
    feed_url = Keyword.get(opts, :feed_url)

    with {:ok, document} <- parse_document(xml_body),
         {:ok, payload} <- parse_root(document, feed_url) do
      {:ok, payload}
    end
  end

  defp parse_document(xml_body) do
    try do
      xml_bytes = xml_body |> IO.iodata_to_binary() |> :binary.bin_to_list()
      {document, _rest} = :xmerl_scan.string(xml_bytes)
      {:ok, document}
    rescue
      _ -> {:error, "Could not parse feed XML"}
    catch
      :exit, _ -> {:error, "Could not parse feed XML"}
    end
  end

  defp parse_root(document, feed_url) do
    case local_name(document) do
      "rss" -> {:ok, parse_rss(document, feed_url)}
      "feed" -> {:ok, parse_atom(document, feed_url)}
      "RDF" -> {:ok, parse_rss(document, feed_url)}
      _ -> {:error, "This URL does not appear to be a valid RSS/Atom feed"}
    end
  end

  defp parse_rss(root, feed_url) do
    channel = first_child_by_name(root, "channel") || root
    site_url = first_child_text(channel, ["link"]) |> resolve_url(feed_url)
    base_url = origin_url(site_url) || origin_url(feed_url)

    icon_url =
      case first_child_by_name(channel, "image") do
        nil -> nil
        image -> first_child_text(image, ["url"])
      end

    entries =
      root
      |> rss_item_elements(channel)
      |> Enum.map(&parse_entry(&1, feed_url, base_url))

    %{
      title: first_child_text(channel, ["title"]),
      site_url: site_url,
      base_url: base_url,
      favicon_url: resolve_url(icon_url, base_url) || favicon_url_for(base_url),
      entries: entries
    }
  end

  defp rss_item_elements(root, channel) do
    channel_items =
      channel
      |> child_elements()
      |> Enum.filter(&(local_name(&1) == "item"))

    if channel_items == [] and local_name(root) == "RDF" do
      root
      |> child_elements()
      |> Enum.filter(&(local_name(&1) == "item"))
    else
      channel_items
    end
  end

  defp parse_atom(root, feed_url) do
    site_url = first_alternate_link(root, feed_url) || first_link_text(root, feed_url)
    base_url = origin_url(site_url) || origin_url(feed_url)

    entries =
      root
      |> child_elements()
      |> Enum.filter(&(local_name(&1) == "entry"))
      |> Enum.map(&parse_entry(&1, feed_url, base_url))

    %{
      title: first_child_text(root, ["title"]),
      site_url: site_url,
      base_url: base_url,
      favicon_url:
        first_child_text(root, ["icon", "logo"])
        |> resolve_url(base_url)
        |> fallback_favicon(base_url),
      entries: entries
    }
  end

  defp parse_entry(entry, feed_url, base_url) do
    link =
      first_alternate_link(entry, feed_url || base_url) ||
        first_link_text(entry, feed_url || base_url)

    title = first_child_text(entry, ["title"]) || "(untitled)"
    raw_guid = first_child_text(entry, ["guid", "id"])

    published_at =
      entry
      |> first_child_text(["published", "updated", "pubDate", "date"])
      |> parse_datetime()

    guid = raw_guid || link || synthetic_guid(title, published_at)

    summary_html = first_child_text(entry, ["summary", "description"])
    content_html = first_child_text(entry, ["content", "encoded", "description", "summary"])

    %{
      guid: guid,
      url: link,
      title: title,
      author: parse_author(entry),
      summary_html: summary_html,
      content_html: content_html,
      published_at: published_at
    }
  end

  defp parse_author(entry) do
    author_element = first_child_by_name(entry, "author")

    cond do
      is_nil(author_element) ->
        first_child_text(entry, ["author", "creator"])

      true ->
        first_child_text(author_element, ["name"]) || text_content(author_element)
    end
  end

  defp first_alternate_link(element, base_url) do
    element
    |> child_elements()
    |> Enum.filter(&(local_name(&1) == "link"))
    |> Enum.find_value(fn link_element ->
      rel = attribute(link_element, "rel")
      href = attribute(link_element, "href")

      if is_binary(href) and (is_nil(rel) or rel == "" or String.downcase(rel) == "alternate") do
        resolve_url(href, base_url)
      end
    end)
  end

  defp first_link_text(element, base_url) do
    element
    |> child_elements()
    |> Enum.filter(&(local_name(&1) == "link"))
    |> Enum.find_value(fn link_element ->
      href = attribute(link_element, "href")

      cond do
        is_binary(href) ->
          resolve_url(href, base_url)

        true ->
          link_element
          |> text_content()
          |> resolve_url(base_url)
      end
    end)
  end

  defp attribute(element, attr_name) do
    element
    |> xmlElement(:attributes)
    |> Enum.find_value(fn attribute ->
      if local_name(attribute) == attr_name do
        attribute |> xmlAttribute(:value) |> to_string() |> String.trim() |> blank_to_nil()
      end
    end)
  end

  defp first_child_text(element, names) when is_list(names) do
    Enum.find_value(names, fn name ->
      element
      |> first_child_by_name(name)
      |> case do
        nil -> nil
        child -> text_content(child)
      end
    end)
  end

  defp first_child_by_name(element, name) do
    Enum.find(child_elements(element), &(local_name(&1) == name))
  end

  defp child_elements(element) do
    element
    |> xmlElement(:content)
    |> Enum.filter(&match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
  end

  defp text_content(nil), do: nil

  defp text_content(element) do
    element
    |> collect_text([])
    |> Enum.reverse()
    |> to_string()
    |> String.trim()
    |> blank_to_nil()
  end

  defp collect_text(node, acc) when is_tuple(node) do
    cond do
      match?({:xmlText, _, _, _, _, _}, node) ->
        [xmlText(node, :value) | acc]

      match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, node) ->
        Enum.reduce(xmlElement(node, :content), acc, &collect_text/2)

      true ->
        acc
    end
  end

  defp local_name(node) when is_tuple(node) do
    case elem(node, 0) do
      :xmlElement ->
        node
        |> xmlElement(:name)
        |> Atom.to_string()
        |> split_local_name()

      :xmlAttribute ->
        node
        |> xmlAttribute(:name)
        |> Atom.to_string()
        |> split_local_name()
    end
  end

  defp split_local_name(value) do
    value
    |> String.split(":")
    |> List.last()
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      true ->
        parse_iso_datetime(trimmed) || parse_http_date(trimmed)
    end
  end

  defp parse_iso_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive_datetime} ->
            DateTime.from_naive!(naive_datetime, "Etc/UTC")

          _ ->
            nil
        end
    end
  end

  defp parse_http_date(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      :bad_date ->
        nil

      {{year, month, day}, {hour, minute, second}} ->
        naive_datetime = NaiveDateTime.new!(year, month, day, hour, minute, second)
        DateTime.from_naive!(naive_datetime, "Etc/UTC")
    end
  end

  defp resolve_url(nil, _base), do: nil

  defp resolve_url(url, base) when is_binary(url) do
    trimmed = String.trim(url)
    uri = URI.parse(trimmed)

    cond do
      trimmed == "" ->
        nil

      uri.scheme in ["http", "https"] ->
        URI.to_string(uri)

      is_binary(uri.host) and uri.host != "" ->
        URI.to_string(%URI{uri | scheme: uri.scheme || "https"})

      is_binary(base) and base != "" ->
        URI.merge(base, trimmed) |> URI.to_string()

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  defp origin_url(nil), do: nil

  defp origin_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        "#{scheme}://#{host}"

      _ ->
        nil
    end
  end

  defp synthetic_guid(title, published_at) do
    data =
      case published_at do
        %DateTime{} = datetime -> "#{title}|#{DateTime.to_iso8601(datetime)}"
        _ -> title
      end

    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp fallback_favicon(nil, base_url), do: favicon_url_for(base_url)
  defp fallback_favicon(value, _base_url) when is_binary(value), do: value

  defp fallback_favicon(_, base_url), do: favicon_url_for(base_url)

  defp favicon_url_for(nil), do: nil
  defp favicon_url_for(base_url), do: base_url <> "/favicon.ico"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end
end
