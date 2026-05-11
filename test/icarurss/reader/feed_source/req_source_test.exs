defmodule Icarurss.Reader.FeedSource.ReqSourceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Icarurss.Reader.FeedSource.ReqSource

  setup do
    original = Application.get_env(:icarurss, :feed_fetch)

    on_exit(fn ->
      Application.put_env(:icarurss, :feed_fetch, original)
    end)

    :ok
  end

  test "streams feed entries through the callback" do
    rss = """
    <rss version="2.0">
      <channel>
        <title>Streamed</title>
        <link>https://example.com</link>
        <item><guid>one</guid><title>One</title></item>
        <item><guid>two</guid><title>Two</title></item>
      </channel>
    </rss>
    """

    put_req_plug(fn conn -> Plug.Conn.send_resp(conn, 200, rss) end)

    callback = fn entry, acc -> [entry.guid | acc] end

    assert {:ok, payload, acc, meta} =
             ReqSource.fetch_feed("https://example.com/feed.xml",
               on_entry: callback,
               entry_acc: []
             )

    assert payload.title == "Streamed"
    assert payload.entries == []
    assert Enum.sort(acc) == ["one", "two"]
    assert meta.http_status == 200
    assert meta.parsed_items == 2
    assert meta.bytes > 0
  end

  test "enriches direct feed favicons from the feed site html" do
    rss = """
    <rss version="2.0">
      <channel>
        <title>Site Icon</title>
        <link>https://example.com</link>
        <item><guid>one</guid><title>One</title></item>
      </channel>
    </rss>
    """

    html = """
    <html>
      <head>
        <link rel="shortcut icon" href="/assets/site-icon.png" />
      </head>
    </html>
    """

    put_req_plug(fn
      %{request_path: "/feed.xml"} = conn ->
        Plug.Conn.send_resp(conn, 200, rss)

      %{request_path: path} = conn when path in [nil, "", "/"] ->
        Plug.Conn.send_resp(conn, 200, html)

      conn ->
        Plug.Conn.send_resp(conn, 404, "not found")
    end)

    assert {:ok, payload, _acc, _meta} = ReqSource.fetch_feed("https://example.com/feed.xml", [])
    assert payload.favicon_url == "https://example.com/assets/site-icon.png"
  end

  test "drops the conventional favicon fallback when it is not reachable" do
    rss = """
    <rss version="2.0">
      <channel>
        <title>No Icon</title>
        <link>https://example.com</link>
        <item><guid>one</guid><title>One</title></item>
      </channel>
    </rss>
    """

    html = "<html><head><title>No icon here</title></head></html>"

    put_req_plug(fn
      %{request_path: "/feed.xml"} = conn -> Plug.Conn.send_resp(conn, 200, rss)
      %{request_path: "/"} = conn -> Plug.Conn.send_resp(conn, 200, html)
      %{request_path: "/favicon.ico"} = conn -> Plug.Conn.send_resp(conn, 404, "not found")
      conn -> Plug.Conn.send_resp(conn, 404, "not found")
    end)

    assert {:ok, payload, _acc, _meta} = ReqSource.fetch_feed("https://example.com/feed.xml", [])
    assert payload.favicon_url == nil
  end

  test "returns an error for non-success status" do
    put_req_plug(fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)

    assert {:error, reason, meta} = ReqSource.fetch_feed("https://example.com/feed.xml", [])
    assert reason == "Request failed with status 503"
    assert meta.http_status == 503
  end

  test "stops when the response exceeds the max byte limit" do
    rss = ~s|<rss version="2.0"><channel><title>Too Large</title></channel></rss>|
    put_req_plug(fn conn -> Plug.Conn.send_resp(conn, 200, rss) end)

    assert {:error, reason, meta} =
             ReqSource.fetch_feed("https://example.com/feed.xml", max_bytes: 10)

    assert reason =~ "exceeded max size"
    assert meta.bytes > 10
  end

  test "stops gracefully at the max item limit" do
    rss = """
    <rss version="2.0">
      <channel>
        <title>Limited</title>
        <link>https://example.com</link>
        <item><guid>one</guid><title>One</title></item>
        <item><guid>two</guid><title>Two</title></item>
      </channel>
    </rss>
    """

    put_req_plug(fn conn -> Plug.Conn.send_resp(conn, 200, rss) end)

    callback = fn entry, acc -> [entry.guid | acc] end

    assert {:ok, _payload, acc, meta} =
             ReqSource.fetch_feed("https://example.com/feed.xml",
               max_items: 1,
               on_entry: callback,
               entry_acc: []
             )

    assert acc == ["one"]
    assert meta.parsed_items == 1
    assert meta.halted_reason == {:max_items, 1}
  end

  test "returns malformed XML errors without crashing" do
    put_req_plug(fn conn -> Plug.Conn.send_resp(conn, 200, "<rss><channel>") end)

    log =
      capture_log(fn ->
        assert {:error, reason, _meta} = ReqSource.fetch_feed("https://example.com/feed.xml", [])
        assert reason =~ "Could not parse feed XML"
      end)

    assert log == ""
  end

  defp put_req_plug(plug) do
    Application.put_env(:icarurss, :feed_fetch,
      connect_timeout: 5_000,
      pool_timeout: 5_000,
      receive_timeout: 30_000,
      max_bytes: 25_000_000,
      max_items: 500,
      retry: false,
      req_options: [plug: plug]
    )
  end
end
