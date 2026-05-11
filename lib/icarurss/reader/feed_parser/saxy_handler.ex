defmodule Icarurss.Reader.FeedParser.SaxyHandler do
  @moduledoc false

  @behaviour Saxy.Handler

  alias Icarurss.Reader.FeedParser

  def initial_state(opts) do
    %{
      feed_url: Keyword.get(opts, :feed_url),
      max_items: Keyword.get(opts, :max_items),
      entry_callback: Keyword.get(opts, :on_entry),
      entry_acc: Keyword.get(opts, :entry_acc),
      root_name: nil,
      stack: [],
      feed_fields: %{},
      current_entry: nil,
      entries: [],
      entry_count: 0,
      parse_error: nil,
      halted_reason: nil
    }
  end

  @impl true
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  def handle_event(:end_document, _data, state), do: {:ok, state}

  def handle_event(:start_element, {name, attributes}, state) do
    local = FeedParser.local_name(name)
    frame = %{name: name, local: local, attrs: Map.new(attributes), chunks: []}
    stack = [frame | state.stack]
    path = path_from_stack(stack)

    state =
      state
      |> maybe_set_root(local)
      |> Map.put(:stack, stack)
      |> maybe_start_entry(local, path)

    {:ok, state}
  end

  def handle_event(:characters, chars, state), do: handle_text(chars, state)
  def handle_event(:cdata, chars, state), do: handle_text(chars, state)

  def handle_event(:end_element, _name, %{stack: []} = state), do: {:ok, state}

  def handle_event(:end_element, _name, state) do
    [frame | rest] = state.stack
    text = frame.chunks |> Enum.reverse() |> IO.iodata_to_binary()
    path = path_from_stack(state.stack)

    state =
      %{state | stack: append_text_to_stack(rest, text)}
      |> capture_entry_field(path, frame, text)
      |> capture_feed_field(path, frame, text)

    if entry_root_closing?(state.current_entry, path) do
      state = finalize_entry(state)

      case state.halted_reason do
        nil -> {:ok, state}
        _reason -> {:stop, state}
      end
    else
      {:ok, state}
    end
  end

  defp maybe_set_root(%{root_name: nil} = state, local), do: %{state | root_name: local}
  defp maybe_set_root(state, _local), do: state

  defp maybe_start_entry(%{current_entry: nil} = state, "item", path) do
    if rss_item_path?(state.root_name, path) do
      %{state | current_entry: %{type: :rss, root_depth: length(path), fields: %{}}}
    else
      state
    end
  end

  defp maybe_start_entry(%{current_entry: nil} = state, "entry", path) do
    if path == ["feed", "entry"] do
      %{state | current_entry: %{type: :atom, root_depth: length(path), fields: %{}}}
    else
      state
    end
  end

  defp maybe_start_entry(state, _local, _path), do: state

  defp rss_item_path?("rss", path), do: path == ["rss", "channel", "item"]
  defp rss_item_path?("RDF", path), do: path == ["RDF", "item"]
  defp rss_item_path?(_root, _path), do: false

  defp capture_entry_field(%{current_entry: nil} = state, _path, _frame, _text), do: state

  defp capture_entry_field(%{current_entry: entry} = state, path, frame, text) do
    relative_path = Enum.drop(path, entry.root_depth)

    fields =
      entry.fields
      |> maybe_put_entry_text(relative_path, text)
      |> maybe_put_entry_link(relative_path, frame, text)

    %{state | current_entry: %{entry | fields: fields}}
  end

  defp maybe_put_entry_text(fields, ["title"], text),
    do: FeedParser.put_first_present(fields, "title", text)

  defp maybe_put_entry_text(fields, ["guid"], text),
    do: FeedParser.put_first_present(fields, "guid", text)

  defp maybe_put_entry_text(fields, ["id"], text),
    do: FeedParser.put_first_present(fields, "id", text)

  defp maybe_put_entry_text(fields, ["published"], text),
    do: FeedParser.put_first_present(fields, "published", text)

  defp maybe_put_entry_text(fields, ["updated"], text),
    do: FeedParser.put_first_present(fields, "updated", text)

  defp maybe_put_entry_text(fields, ["pubDate"], text),
    do: FeedParser.put_first_present(fields, "pubDate", text)

  defp maybe_put_entry_text(fields, ["date"], text),
    do: FeedParser.put_first_present(fields, "date", text)

  defp maybe_put_entry_text(fields, ["summary"], text),
    do: FeedParser.put_first_present(fields, "summary", text)

  defp maybe_put_entry_text(fields, ["description"], text),
    do: FeedParser.put_first_present(fields, "description", text)

  defp maybe_put_entry_text(fields, ["content"], text),
    do: FeedParser.put_first_present(fields, "content", text)

  defp maybe_put_entry_text(fields, ["encoded"], text),
    do: FeedParser.put_first_present(fields, "encoded", text)

  defp maybe_put_entry_text(fields, ["author"], text),
    do: FeedParser.put_first_present(fields, "author", text)

  defp maybe_put_entry_text(fields, ["author", "name"], text),
    do: FeedParser.put_first_present(fields, "author_name", text)

  defp maybe_put_entry_text(fields, ["creator"], text),
    do: FeedParser.put_first_present(fields, "creator", text)

  defp maybe_put_entry_text(fields, _path, _text), do: fields

  defp maybe_put_entry_link(fields, ["link"], frame, text), do: put_link(fields, frame, text)
  defp maybe_put_entry_link(fields, _path, _frame, _text), do: fields

  defp capture_feed_field(%{current_entry: nil} = state, path, frame, text) do
    fields =
      state.feed_fields
      |> maybe_put_feed_text(state.root_name, path, text)
      |> maybe_put_feed_link(state.root_name, path, frame, text)

    %{state | feed_fields: fields}
  end

  defp capture_feed_field(state, _path, _frame, _text), do: state

  defp maybe_put_feed_text(fields, "rss", ["rss", "channel", "title"], text),
    do: FeedParser.put_first_present(fields, "title", text)

  defp maybe_put_feed_text(fields, "rss", ["rss", "channel", "link"], text),
    do: FeedParser.put_first_present(fields, "link", text)

  defp maybe_put_feed_text(fields, "rss", ["rss", "channel", "image", "url"], text),
    do: FeedParser.put_first_present(fields, "image_url", text)

  defp maybe_put_feed_text(fields, "RDF", ["RDF", "channel", "title"], text),
    do: FeedParser.put_first_present(fields, "title", text)

  defp maybe_put_feed_text(fields, "RDF", ["RDF", "channel", "link"], text),
    do: FeedParser.put_first_present(fields, "link", text)

  defp maybe_put_feed_text(fields, "feed", ["feed", "title"], text),
    do: FeedParser.put_first_present(fields, "title", text)

  defp maybe_put_feed_text(fields, "feed", ["feed", "icon"], text),
    do: FeedParser.put_first_present(fields, "icon", text)

  defp maybe_put_feed_text(fields, "feed", ["feed", "logo"], text),
    do: FeedParser.put_first_present(fields, "logo", text)

  defp maybe_put_feed_text(fields, _root, _path, _text), do: fields

  defp maybe_put_feed_link(fields, "feed", ["feed", "link"], frame, text),
    do: put_link(fields, frame, text)

  defp maybe_put_feed_link(fields, _root, _path, _frame, _text), do: fields

  defp put_link(fields, frame, text) do
    link = %{
      "href" => Map.get(frame.attrs, "href"),
      "rel" => Map.get(frame.attrs, "rel"),
      "text" => text
    }

    Map.update(fields, "links", [link], &(&1 ++ [link]))
  end

  defp entry_root_closing?(nil, _path), do: false

  defp entry_root_closing?(%{root_depth: root_depth}, path), do: length(path) == root_depth

  defp finalize_entry(%{current_entry: entry} = state) do
    base_url = FeedParser.feed_payload(state).base_url
    parsed_entry = FeedParser.entry_from_fields(entry.fields, state.feed_url, base_url)

    state =
      case state.entry_callback do
        callback when is_function(callback, 2) ->
          %{state | entry_acc: callback.(parsed_entry, state.entry_acc)}

        _ ->
          %{state | entries: [parsed_entry | state.entries]}
      end

    state = %{state | entry_count: state.entry_count + 1, current_entry: nil}

    if max_items_reached?(state) do
      %{state | halted_reason: {:max_items, state.max_items}}
    else
      state
    end
  end

  defp max_items_reached?(%{max_items: max_items, entry_count: entry_count})
       when is_integer(max_items) and max_items > 0 do
    entry_count >= max_items
  end

  defp max_items_reached?(_state), do: false

  defp handle_text(text, state) do
    if invalid_xml_text?(text) do
      {:stop, %{state | parse_error: "Could not parse feed XML: invalid XML character"}}
    else
      {:ok, append_text(state, text)}
    end
  end

  defp invalid_xml_text?(text) do
    String.match?(text, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/)
  end

  defp append_text(%{stack: []} = state, _text), do: state
  defp append_text(state, text), do: %{state | stack: append_text_to_stack(state.stack, text)}

  defp append_text_to_stack([], _text), do: []

  defp append_text_to_stack([frame | rest], text) do
    [%{frame | chunks: [text | frame.chunks]} | rest]
  end

  defp path_from_stack(stack) do
    stack
    |> Enum.reverse()
    |> Enum.map(& &1.local)
  end
end
