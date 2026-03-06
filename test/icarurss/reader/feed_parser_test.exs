defmodule Icarurss.Reader.FeedParserTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Icarurss.Reader.FeedParser

  describe "parse/2" do
    test "parses RSS feeds with items and metadata" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>RSS Example</title>
          <link>https://example.com</link>
          <item>
            <guid>guid-1</guid>
            <title>Article One</title>
            <link>https://example.com/articles/1</link>
            <pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>
            <description><![CDATA[<p>Summary One</p>]]></description>
            <content:encoded><![CDATA[<p>Content One</p>]]></content:encoded>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, payload} = FeedParser.parse(rss, feed_url: "https://example.com/feed.xml")
      assert payload.title == "RSS Example"
      assert payload.site_url == "https://example.com"
      assert payload.base_url == "https://example.com"
      assert payload.favicon_url == "https://example.com/favicon.ico"
      assert length(payload.entries) == 1

      entry = hd(payload.entries)
      assert entry.guid == "guid-1"
      assert entry.title == "Article One"
      assert entry.url == "https://example.com/articles/1"
      assert entry.summary_html == "<p>Summary One</p>"
      assert entry.content_html == "<p>Content One</p>"
      assert %DateTime{} = entry.published_at
    end

    test "parses long-form RSS pubDate values without timezone" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>RSS Example</title>
          <link>https://example.com</link>
          <item>
            <guid>guid-1</guid>
            <title>Article One</title>
            <link>https://example.com/articles/1</link>
            <pubDate>Thursday, March 5, 2026 - 16:28</pubDate>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, payload} = FeedParser.parse(rss, feed_url: "https://example.com/feed.xml")
      assert [entry] = payload.entries
      assert entry.published_at == ~U[2026-03-05 16:28:00Z]
    end

    test "parses RFC-style RSS pubDate values with numeric timezone offsets" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>RSS Example</title>
          <link>https://example.com</link>
          <item>
            <guid>guid-1</guid>
            <title>Article One</title>
            <link>https://example.com/articles/1</link>
            <pubDate>Sun, 14 Jan 2024 12:14:05 -0600</pubDate>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, payload} = FeedParser.parse(rss, feed_url: "https://example.com/feed.xml")
      assert [entry] = payload.entries
      assert entry.published_at == ~U[2024-01-14 18:14:05Z]
    end

    test "parses RFC-style RSS pubDate values without a weekday" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>RSS Example</title>
          <link>https://example.com</link>
          <item>
            <guid>guid-1</guid>
            <title>Article One</title>
            <link>https://example.com/articles/1</link>
            <pubDate>27 Feb 2026 00:00:00 UT</pubDate>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, payload} = FeedParser.parse(rss, feed_url: "https://example.com/feed.xml")
      assert [entry] = payload.entries
      assert entry.published_at == ~U[2026-02-27 00:00:00Z]
    end

    test "parses RSS feeds containing UTF-8 punctuation in text nodes" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Unicode Feed</title>
          <link>https://example.com</link>
          <item>
            <title>A – B</title>
            <link>https://example.com/articles/1</link>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, payload} = FeedParser.parse(rss, feed_url: "https://example.com/feed.xml")
      assert [entry] = payload.entries
      assert entry.title == "A – B"
    end

    test "parses Atom feeds with href links and updated timestamps" do
      atom = """
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom Example</title>
        <link href="https://atom.example.com" rel="alternate" />
        <entry>
          <id>tag:atom.example.com,2026:1</id>
          <title>Atom Entry</title>
          <link href="/posts/1" rel="alternate" />
          <updated>2026-02-14T10:00:00Z</updated>
          <summary>Atom summary</summary>
          <content>Atom content</content>
          <author><name>Atom Author</name></author>
        </entry>
      </feed>
      """

      assert {:ok, payload} = FeedParser.parse(atom, feed_url: "https://atom.example.com/feed")
      assert payload.title == "Atom Example"
      assert payload.site_url == "https://atom.example.com"
      assert payload.base_url == "https://atom.example.com"
      assert payload.favicon_url == "https://atom.example.com/favicon.ico"

      assert [entry] = payload.entries
      assert entry.guid == "tag:atom.example.com,2026:1"
      assert entry.url == "https://atom.example.com/posts/1"
      assert entry.author == "Atom Author"
      assert entry.summary_html == "Atom summary"
      assert entry.content_html == "Atom content"
      assert %DateTime{} = entry.published_at
    end

    test "parses RDF RSS feeds with root-level items" do
      rdf = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rdf:RDF
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        xmlns="http://purl.org/rss/1.0/"
      >
        <channel rdf:about="https://example.org/">
          <title>RDF Example</title>
          <link>https://example.org/</link>
          <description>Example RSS 1.0 feed</description>
        </channel>
        <item rdf:about="https://example.org/posts/1">
          <title>RDF Entry</title>
          <link>https://example.org/posts/1</link>
          <description>RDF summary</description>
        </item>
      </rdf:RDF>
      """

      assert {:ok, payload} = FeedParser.parse(rdf, feed_url: "https://example.org/feed.rdf")
      assert payload.title == "RDF Example"
      assert payload.site_url == "https://example.org/"
      assert payload.base_url == "https://example.org"
      assert [entry] = payload.entries
      assert entry.title == "RDF Entry"
      assert entry.url == "https://example.org/posts/1"
      assert entry.summary_html == "RDF summary"
    end

    test "returns an error for non-feed payloads" do
      assert {:error, _reason} = FeedParser.parse("<html><body>not a feed</body></html>")
    end

    test "returns an error instead of crashing on invalid XML characters" do
      invalid_xml =
        "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Bad" <>
          <<1>> <> "</title></channel></rss>"

      log = capture_log(fn -> assert {:error, _reason} = FeedParser.parse(invalid_xml) end)
      assert log =~ "fatal"
    end
  end
end
