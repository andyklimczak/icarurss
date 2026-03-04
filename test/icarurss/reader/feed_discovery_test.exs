defmodule Icarurss.Reader.FeedDiscoveryTest do
  use ExUnit.Case, async: true

  alias Icarurss.Reader.FeedDiscovery

  describe "discover_from_html/2" do
    test "extracts feed link candidates and resolves relative URLs" do
      html = """
      <html>
        <head>
          <link rel="alternate" type="application/rss+xml" title="Main Feed" href="/feed.xml" />
          <link rel="alternate stylesheet" type="application/atom+xml" href="https://example.com/atom.xml" />
          <link rel="icon" href="/favicon.ico" />
        </head>
      </html>
      """

      candidates = FeedDiscovery.discover_from_html(html, "https://example.com/blog")

      assert length(candidates) == 2

      assert %{
               feed_url: "https://example.com/feed.xml",
               title: "Main Feed",
               site_url: "https://example.com",
               base_url: "https://example.com",
               favicon_url: "https://example.com/favicon.ico"
             } in candidates

      assert Enum.any?(candidates, &(&1.feed_url == "https://example.com/atom.xml"))
    end

    test "returns an empty list when no feed links are present" do
      html = "<html><head><title>No Feeds</title></head><body></body></html>"
      assert FeedDiscovery.discover_from_html(html, "https://example.com") == []
    end
  end

  describe "candidate_from_feed_payload/2" do
    test "maps normalized payload fields" do
      payload = %{
        title: "Example Feed",
        site_url: "https://example.com",
        base_url: "https://example.com",
        favicon_url: "https://example.com/favicon.ico"
      }

      candidate =
        FeedDiscovery.candidate_from_feed_payload("https://example.com/feed.xml", payload)

      assert candidate.feed_url == "https://example.com/feed.xml"
      assert candidate.title == "Example Feed"
      assert candidate.site_url == "https://example.com"
      assert candidate.base_url == "https://example.com"
      assert candidate.favicon_url == "https://example.com/favicon.ico"
    end
  end
end
