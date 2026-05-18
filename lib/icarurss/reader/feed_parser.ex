defmodule Icarurss.Reader.FeedParser do
  @moduledoc """
  Parses RSS/Atom XML into normalized feed metadata and entries.

  Feed refreshes use `parse_stream/2` so HTTP chunks can be parsed incrementally without building
  a full XML tree. `parse/2` is kept as a compatibility wrapper for discovery and tests.
  """

  alias Icarurss.Reader.FeedParser.SaxyHandler
  alias Icarurss.Reader.RefreshError

  @type entry_acc :: term()
  @type entry_callback :: (map(), entry_acc() -> entry_acc())
  @type normalizer_state :: %{started?: boolean(), pending: binary(), preview: binary()}

  @doc false
  def new_stream_normalizer_state do
    %{started?: false, pending: "", preview: ""}
  end

  @doc false
  def normalize_stream_chunk(data, %{started?: false, pending: pending} = state)
      when is_binary(data) do
    buffer =
      pending
      |> Kernel.<>(data)
      |> strip_leading_bom()
      |> strip_invalid_xml_controls()

    preview = preview(buffer)

    cond do
      obvious_non_feed?(buffer) ->
        {:error, non_feed_error(preview), %{state | pending: "", preview: preview}}

      xml_start = xml_start_position(buffer) ->
        normalized =
          buffer
          |> binary_part(xml_start, byte_size(buffer) - xml_start)
          |> remove_extra_xml_declarations(:keep_leading)

        {:cont, normalized, %{state | started?: true, pending: "", preview: preview}}

      byte_size(buffer) >= 1024 ->
        {:error, non_feed_error(preview), %{state | pending: "", preview: preview}}

      true ->
        {:cont, "", %{state | pending: buffer, preview: preview}}
    end
  end

  def normalize_stream_chunk(data, %{started?: true} = state) when is_binary(data) do
    normalized =
      data
      |> strip_invalid_xml_controls()
      |> remove_extra_xml_declarations(:drop_all)

    {:cont, normalized, %{state | preview: preview(state.preview <> data)}}
  end

  @doc false
  def escaped_preview(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.slice(0, 240)
  end

  @spec parse(binary(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def parse(xml_body, opts \\ []) when is_binary(xml_body) do
    parse_stream([xml_body], opts)
  end

  @spec parse_stream(Enumerable.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def parse_stream(chunks, opts \\ []) do
    initial_state = SaxyHandler.initial_state(opts)
    saxy_opts = [character_data_max_length: Keyword.get(opts, :character_data_max_length, 65_536)]

    case Saxy.parse_stream(chunks, SaxyHandler, initial_state, saxy_opts) do
      {:ok, state} ->
        payload_from_state(state)

      {:halt, state, _rest} ->
        payload_from_state(state)

      {:error, error} ->
        {:error, "Could not parse feed XML: #{Exception.message(error)}"}
    end
  rescue
    error in Saxy.ParseError ->
      {:error, "Could not parse feed XML: #{Exception.message(error)}"}

    _error ->
      {:error, "Could not parse feed XML"}
  end

  @doc false
  def payload_from_state(%{root_name: root_name} = state) do
    cond do
      is_binary(Map.get(state, :parse_error)) ->
        {:error, state.parse_error}

      valid_root?(root_name) ->
        {:ok, feed_payload(state)}

      true ->
        {:error, "This URL does not appear to be a valid RSS/Atom feed"}
    end
  end

  @doc false
  def feed_payload(state) do
    feed_url = state.feed_url
    feed = state.feed_fields
    site_url = feed_site_url(feed, feed_url)
    base_url = origin_url(site_url) || origin_url(feed_url)

    %{
      title: first_present(feed, ["title"]),
      site_url: site_url,
      base_url: base_url,
      favicon_url: feed_favicon_url(feed, base_url),
      entries: Enum.reverse(state.entries || [])
    }
  end

  @doc false
  def entry_from_fields(fields, feed_url, base_url) do
    link = entry_link(fields, feed_url || base_url)
    title = first_present(fields, ["title"]) || "(untitled)"
    raw_guid = first_present(fields, ["guid", "id"])

    published_at =
      fields
      |> first_present(["published", "updated", "pubDate", "date"])
      |> parse_datetime()

    %{
      guid: raw_guid || link || synthetic_guid(title, published_at),
      url: link,
      title: title,
      author: entry_author(fields),
      summary_html: first_present(fields, ["summary", "description"]),
      content_html: first_present(fields, ["content", "encoded", "description", "summary"]),
      published_at: published_at
    }
  end

  @doc false
  def put_first_present(map, key, value) when is_binary(key) do
    case blank_to_nil(value) do
      nil -> map
      value -> Map.put_new(map, key, value)
    end
  end

  @doc false
  def local_name(value) when is_binary(value) do
    value
    |> String.split(":")
    |> List.last()
  end

  defp valid_root?(root_name), do: root_name in ["rss", "feed", "RDF"]

  defp strip_leading_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_leading_bom(binary), do: binary

  defp strip_invalid_xml_controls(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reject(&invalid_xml_control?/1)
    |> :binary.list_to_bin()
  end

  defp invalid_xml_control?(byte) do
    byte in 0x00..0x08 or byte in [0x0B, 0x0C] or byte in 0x0E..0x1F
  end

  defp xml_start_position(buffer) do
    ["<?xml", "<rss", "<feed", "<rdf:RDF", "<RDF"]
    |> Enum.map(&:binary.match(buffer, &1))
    |> Enum.filter(&match?({_, _}, &1))
    |> Enum.map(fn {position, _length} -> position end)
    |> Enum.min(fn -> nil end)
  end

  defp obvious_non_feed?(buffer) do
    trimmed = String.trim_leading(buffer)
    downcased = String.downcase(binary_part(trimmed, 0, min(byte_size(trimmed), 80)))

    String.starts_with?(downcased, "<!doctype html") or
      String.starts_with?(downcased, "<html") or
      (byte_size(buffer) >= 64 and not String.contains?(buffer, "<"))
  end

  defp non_feed_error(preview) do
    RefreshError.new(:non_feed, "This URL does not appear to be a valid RSS/Atom feed",
      meta: %{preview_start: escaped_preview(preview), halted_reason: :non_feed}
    )
  end

  defp remove_extra_xml_declarations(binary, :keep_leading) do
    case Regex.run(~r/\A<\?xml\s+[^?]*\?>/i, binary, return: :index) do
      [{0, length}] ->
        declaration = binary_part(binary, 0, length)
        rest = binary_part(binary, length, byte_size(binary) - length)
        declaration <> remove_extra_xml_declarations(rest, :drop_all)

      _ ->
        remove_extra_xml_declarations(binary, :drop_all)
    end
  end

  defp remove_extra_xml_declarations(binary, :drop_all) do
    Regex.replace(~r/<\?xml\s+[^?]*\?>/i, binary, "")
  end

  defp preview(binary), do: binary_part(binary, 0, min(byte_size(binary), 240))

  defp feed_site_url(feed, feed_url) do
    first_alternate_link(feed, feed_url) ||
      first_link_text(feed, feed_url) ||
      first_present(feed, ["link"]) |> resolve_url(feed_url)
  end

  defp feed_favicon_url(feed, base_url) do
    feed
    |> first_present(["image_url", "icon", "logo"])
    |> resolve_url(base_url)
    |> fallback_favicon(base_url)
  end

  defp entry_link(fields, base_url) do
    first_alternate_link(fields, base_url) ||
      first_link_text(fields, base_url) ||
      first_present(fields, ["link"]) |> resolve_url(base_url)
  end

  defp first_alternate_link(fields, base_url) do
    fields
    |> Map.get("links", [])
    |> Enum.find_value(fn link ->
      href = blank_to_nil(Map.get(link, "href"))
      rel = Map.get(link, "rel") |> to_string() |> String.downcase()

      if is_binary(href) and rel in ["", "alternate"] do
        resolve_url(href, base_url)
      end
    end)
  end

  defp first_link_text(fields, base_url) do
    fields
    |> Map.get("links", [])
    |> Enum.find_value(fn link ->
      href = blank_to_nil(Map.get(link, "href"))
      text = blank_to_nil(Map.get(link, "text"))

      cond do
        is_binary(href) -> resolve_url(href, base_url)
        is_binary(text) -> resolve_url(text, base_url)
        true -> nil
      end
    end)
  end

  defp entry_author(fields) do
    first_present(fields, ["author_name", "author", "creator"])
  end

  defp first_present(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key ->
      map
      |> Map.get(key)
      |> blank_to_nil()
    end)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      true ->
        parse_iso_datetime(trimmed) ||
          parse_rfc822_datetime(trimmed) ||
          parse_rfc822_date_without_weekday(trimmed) ||
          parse_http_date(trimmed) ||
          parse_longform_datetime(trimmed)
    end
  end

  defp parse_iso_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive_datetime} -> DateTime.from_naive!(naive_datetime, "Etc/UTC")
          _ -> nil
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

  defp parse_rfc822_datetime(value) do
    case Regex.named_captures(
           ~r/^(?<weekday>[A-Za-z]{3}),\s+(?<day>\d{1,2})\s+(?<month>[A-Za-z]{3})\s+(?<year>\d{4})\s+(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2}))?\s+(?<offset>Z|UT|UTC|GMT|[+-]\d{4})$/,
           value
         ) do
      %{
        "day" => day,
        "month" => month_name,
        "year" => year,
        "hour" => hour,
        "minute" => minute,
        "offset" => offset
      } = captures ->
        with {:ok, month} <- month_number(month_name),
             {day, ""} <- Integer.parse(day),
             {year, ""} <- Integer.parse(year),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             second <- parse_seconds(captures["second"]),
             {:ok, offset_seconds} <- parse_timezone_offset(offset),
             {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
          naive_datetime
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.add(-offset_seconds, :second)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_rfc822_date_without_weekday(value) do
    case Regex.named_captures(
           ~r/^(?<day>\d{1,2})\s+(?<month>[A-Za-z]{3})\s+(?<year>\d{4})\s+(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2}))?\s+(?<offset>Z|UT|UTC|GMT|[+-]\d{4})$/,
           value
         ) do
      %{
        "day" => day,
        "month" => month_name,
        "year" => year,
        "hour" => hour,
        "minute" => minute,
        "offset" => offset
      } = captures ->
        with {:ok, month} <- month_number(month_name),
             {day, ""} <- Integer.parse(day),
             {year, ""} <- Integer.parse(year),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             second <- parse_seconds(captures["second"]),
             {:ok, offset_seconds} <- parse_timezone_offset(offset),
             {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
          naive_datetime
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.add(-offset_seconds, :second)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_longform_datetime(value) do
    case Regex.named_captures(
           ~r/^(?<weekday>[A-Za-z]+),\s+(?<month>[A-Za-z]+)\s+(?<day>\d{1,2}),\s+(?<year>\d{4})\s+-\s+(?<hour>\d{1,2}):(?<minute>\d{2})(?::(?<second>\d{2}))?$/,
           value
         ) do
      %{
        "month" => month_name,
        "day" => day,
        "year" => year,
        "hour" => hour,
        "minute" => minute
      } = captures ->
        with {:ok, month} <- month_number(month_name),
             {day, ""} <- Integer.parse(day),
             {year, ""} <- Integer.parse(year),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             second <- parse_seconds(captures["second"]),
             {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
          DateTime.from_naive!(naive_datetime, "Etc/UTC")
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp month_number(month_name) do
    case String.downcase(month_name) do
      "jan" -> {:ok, 1}
      "january" -> {:ok, 1}
      "feb" -> {:ok, 2}
      "february" -> {:ok, 2}
      "mar" -> {:ok, 3}
      "march" -> {:ok, 3}
      "apr" -> {:ok, 4}
      "april" -> {:ok, 4}
      "may" -> {:ok, 5}
      "jun" -> {:ok, 6}
      "june" -> {:ok, 6}
      "jul" -> {:ok, 7}
      "july" -> {:ok, 7}
      "aug" -> {:ok, 8}
      "august" -> {:ok, 8}
      "sep" -> {:ok, 9}
      "sept" -> {:ok, 9}
      "september" -> {:ok, 9}
      "oct" -> {:ok, 10}
      "october" -> {:ok, 10}
      "nov" -> {:ok, 11}
      "november" -> {:ok, 11}
      "dec" -> {:ok, 12}
      "december" -> {:ok, 12}
      _ -> :error
    end
  end

  defp parse_timezone_offset(value) when value in ["Z", "UT", "UTC", "GMT"], do: {:ok, 0}

  defp parse_timezone_offset(
         <<sign::binary-size(1), hours::binary-size(2), minutes::binary-size(2)>>
       )
       when sign in ["+", "-"] do
    with {hours, ""} <- Integer.parse(hours),
         {minutes, ""} <- Integer.parse(minutes) do
      total_seconds = hours * 3600 + minutes * 60
      {:ok, if(sign == "-", do: -total_seconds, else: total_seconds)}
    else
      _ -> :error
    end
  end

  defp parse_timezone_offset(_value), do: :error

  defp parse_seconds(nil), do: 0
  defp parse_seconds(""), do: 0
  defp parse_seconds(value) when is_binary(value), do: String.to_integer(value)

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

  defp blank_to_nil(_value), do: nil
end
