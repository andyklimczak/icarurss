defmodule Icarurss.Reader.FeedParserTest do
  use ExUnit.Case, async: true

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

    test "returns an error for non-feed payloads" do
      assert {:error, _reason} = FeedParser.parse("<html><body>not a feed</body></html>")
    end
  end
end
