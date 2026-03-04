defmodule Icarurss.ReaderFixtures do
  @moduledoc false

  alias Icarurss.Reader

  def folder_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Folder #{System.unique_integer([:positive])}",
        position: 0,
        expanded: true
      })

    {:ok, folder} = Reader.create_folder(user, attrs)
    folder
  end

  def feed_fixture(user, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        title: "Feed #{unique}",
        site_url: "https://example#{unique}.com",
        feed_url: "https://example#{unique}.com/feed.xml",
        base_url: "https://example#{unique}.com",
        favicon_url: "https://example#{unique}.com/favicon.ico"
      })

    {:ok, feed} = Reader.create_feed(user, attrs)
    feed
  end

  def article_fixture(user, feed, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        guid: "guid-#{unique}",
        url: "https://example.com/articles/#{unique}",
        title: "Article #{unique}",
        author: "Author #{unique}",
        summary_html: "<p>Summary #{unique}</p>",
        content_html: "<p>Content #{unique}</p>",
        published_at: DateTime.utc_now(:second),
        fetched_at: DateTime.utc_now(:second)
      })

    {:ok, article} = Reader.create_article(user, feed, attrs)
    article
  end
end
