defmodule Icarurss.Reader.Opml do
  @moduledoc false

  require Record

  Record.defrecord(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecord(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  Record.defrecord(
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @spec parse(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse(opml_xml) when is_binary(opml_xml) do
    with {:ok, document} <- parse_document(opml_xml),
         {:ok, body} <- find_body(document) do
      entries =
        body
        |> child_elements()
        |> Enum.filter(&(local_name(&1) == "outline"))
        |> Enum.flat_map(&parse_outline(&1, nil))
        |> Enum.reject(&blank?(&1.feed_url))

      {:ok, entries}
    end
  end

  @spec generate([map()], [map()]) :: String.t()
  def generate(folders, ungrouped_feeds) when is_list(folders) and is_list(ungrouped_feeds) do
    created_at = DateTime.utc_now(:second) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S %z")

    body_lines =
      Enum.flat_map(folders, &folder_outline_lines/1) ++
        Enum.map(ungrouped_feeds, &feed_outline_line(&1, 4))

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>),
      ~s(<opml version="2.0">),
      "  <head>",
      "    <title>Icarurss Subscriptions</title>",
      "    <dateCreated>#{xml_escape(created_at)}</dateCreated>",
      "  </head>",
      "  <body>"
    ]
    |> Kernel.++(body_lines)
    |> Kernel.++(["  </body>", "</opml>"])
    |> Enum.join("\n")
  end

  defp parse_document(opml_xml) do
    try do
      {document, _rest} = :xmerl_scan.string(:binary.bin_to_list(opml_xml), quiet: true)
      {:ok, document}
    rescue
      error -> {:error, "Could not parse OPML document: #{Exception.message(error)}"}
    catch
      :exit, reason -> {:error, "Could not parse OPML document: #{format_parse_error(reason)}"}
    end
  end

  defp format_parse_error({:fatal, {:unexpected_end, _file, line, col}}) do
    "unexpected end of document#{format_location(line, col)}"
  end

  defp format_parse_error({:fatal, {{:endtag_does_not_match, details}, _file, line, col}}) do
    "mismatched closing tag (#{format_endtag_details(details)})#{format_location(line, col)}"
  end

  defp format_parse_error({:fatal, {reason, _file, line, col}}) do
    "#{format_reason(reason)}#{format_location(line, col)}"
  end

  defp format_parse_error(reason), do: inspect(reason)

  defp format_endtag_details({:was, was, :should_have_been, expected}) do
    "got </#{was}> but expected </#{expected}>"
  end

  defp format_endtag_details(details), do: inspect(details)

  defp format_reason(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp format_reason(reason), do: inspect(reason)

  defp format_location({:line, line}, {:col, col}), do: " at line #{line}, column #{col}"
  defp format_location(_line, _col), do: ""

  defp find_body(document) do
    case document |> first_child_by_name("body") do
      nil -> {:error, "Invalid OPML: missing <body> section"}
      body -> {:ok, body}
    end
  end

  defp parse_outline(outline, folder_name) do
    feed_url = attribute(outline, "xmlurl") |> normalize_url()
    title = attribute(outline, "title") || attribute(outline, "text") |> blank_to_nil()
    site_url = attribute(outline, "htmlurl") |> normalize_url()

    if feed_url do
      [
        %{
          folder_name: folder_name,
          feed_url: feed_url,
          title: title,
          site_url: site_url
        }
      ]
    else
      nested_folder_name = folder_name || outline_folder_name(outline)

      outline
      |> child_elements()
      |> Enum.filter(&(local_name(&1) == "outline"))
      |> Enum.flat_map(&parse_outline(&1, nested_folder_name))
    end
  end

  defp outline_folder_name(outline) do
    outline
    |> attribute("title")
    |> case do
      nil -> attribute(outline, "text")
      title -> title
    end
    |> blank_to_nil()
  end

  defp folder_outline_lines(folder) do
    folder_name = folder.name |> to_string() |> blank_to_nil()
    feeds = Map.get(folder, :feeds, [])

    if folder_name && feeds != [] do
      folder_title = xml_escape(folder_name)
      feed_lines = Enum.map(feeds, &feed_outline_line(&1, 6))

      [
        ~s(    <outline text="#{folder_title}" title="#{folder_title}">)
      ] ++ feed_lines ++ ["    </outline>"]
    else
      []
    end
  end

  defp feed_outline_line(feed, indent_size) do
    indent = String.duplicate(" ", indent_size)
    label = feed_label(feed)
    html_url = feed_html_url(feed)

    attrs =
      [
        {"type", "rss"},
        {"text", label},
        {"title", label},
        {"xmlUrl", Map.get(feed, :feed_url)},
        {"htmlUrl", html_url}
      ]
      |> Enum.reject(fn {_key, value} -> blank?(value) end)
      |> Enum.map_join(" ", fn {key, value} ->
        ~s(#{key}="#{xml_escape(value)}")
      end)

    "#{indent}<outline #{attrs} />"
  end

  defp feed_label(feed) do
    Map.get(feed, :title)
    |> blank_to_nil()
    |> case do
      nil -> Map.get(feed, :feed_url)
      title -> title
    end
  end

  defp feed_html_url(feed) do
    Map.get(feed, :site_url)
    |> blank_to_nil()
    |> case do
      nil -> Map.get(feed, :base_url)
      site_url -> site_url
    end
  end

  defp child_elements(element) do
    element
    |> xmlElement(:content)
    |> Enum.filter(&match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
  end

  defp first_child_by_name(element, name) do
    Enum.find(child_elements(element), &(local_name(&1) == name))
  end

  defp attribute(element, name) do
    desired = String.downcase(name)

    element
    |> xmlElement(:attributes)
    |> Enum.find_value(fn attribute ->
      attr_name = attribute |> local_name() |> String.downcase()

      if attr_name == desired do
        attribute
        |> xmlAttribute(:value)
        |> to_string()
        |> String.trim()
        |> blank_to_nil()
      end
    end)
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

      :xmlText ->
        xmlText(node, :value)
        |> to_string()
    end
  end

  defp split_local_name(value) do
    value
    |> String.split(":")
    |> List.last()
  end

  defp normalize_url(nil), do: nil

  defp normalize_url(url) when is_binary(url) do
    trimmed = String.trim(url)
    uri = URI.parse(trimmed)

    cond do
      trimmed == "" ->
        nil

      uri.scheme in ["http", "https"] ->
        URI.to_string(uri)

      is_binary(uri.host) and uri.host != "" ->
        URI.to_string(%URI{uri | scheme: uri.scheme || "https"})

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  defp xml_escape(nil), do: ""

  defp xml_escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp blank?(value), do: is_nil(blank_to_nil(value))

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_to_nil(value), do: value
end
