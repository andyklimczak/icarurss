defmodule Icarurss.ReaderTest do
  use Icarurss.DataCase

  alias Icarurss.Reader
  alias Icarurss.Reader.{Article, Feed, Folder}
  alias Icarurss.Reader.Opml

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  describe "folders" do
    test "create_folder/2 creates a folder scoped to the given user" do
      user = user_fixture()

      assert {:ok, %Folder{} = folder} =
               Reader.create_folder(user, %{name: "Tech", position: 1, expanded: false})

      assert folder.user_id == user.id
      assert folder.name == "Tech"
      assert folder.position == 1
      refute folder.expanded
    end

    test "list_folders_with_feeds/1 preloads only the current user's feeds" do
      user = user_fixture()
      other_user = user_fixture()

      user_folder = folder_fixture(user, %{name: "User Folder"})
      _other_folder = folder_fixture(other_user, %{name: "Other Folder"})

      user_feed = feed_fixture(user, %{folder_id: user_folder.id, title: "User Feed"})
      _other_feed = feed_fixture(other_user, %{title: "Other Feed"})

      folders = Reader.list_folders_with_feeds(user)

      assert [%Folder{} = folder] = folders
      assert folder.id == user_folder.id
      assert [%Feed{} = feed] = folder.feeds
      assert feed.id == user_feed.id
    end
  end

  describe "feeds" do
    test "create_feed/2 supports ungrouped and grouped feeds" do
      user = user_fixture()
      folder = folder_fixture(user)

      assert {:ok, %Feed{} = ungrouped_feed} =
               Reader.create_feed(user, %{feed_url: "https://ungrouped.example.com/feed.xml"})

      assert is_nil(ungrouped_feed.folder_id)

      assert {:ok, %Feed{} = grouped_feed} =
               Reader.create_feed(user, %{
                 folder_id: folder.id,
                 feed_url: "https://grouped.example.com/feed.xml"
               })

      assert grouped_feed.folder_id == folder.id
    end
  end

  describe "articles" do
    test "list_articles_for_user/2 filters by mode and scope" do
      user = user_fixture()
      folder = folder_fixture(user)
      feed = feed_fixture(user, %{folder_id: folder.id, title: "Feed A"})
      other_feed = feed_fixture(user, %{title: "Feed B"})

      unread_in_folder = article_fixture(user, feed, %{title: "Unread in folder", is_read: false})

      _read_in_folder =
        article_fixture(user, feed, %{title: "Read in folder", is_read: true, is_starred: false})

      starred_outside_folder =
        article_fixture(user, other_feed, %{title: "Starred out", is_read: true, is_starred: true})

      assert [%Article{id: id}] =
               Reader.list_articles_for_user(user, filter: :unread, folder_id: folder.id)

      assert id == unread_in_folder.id

      assert [%Article{id: starred_id}] =
               Reader.list_articles_for_user(user, filter: :starred, feed_id: other_feed.id)

      assert starred_id == starred_outside_folder.id
    end

    test "list_articles_for_user/2 supports search against article and feed fields" do
      user = user_fixture()
      feed = feed_fixture(user, %{title: "Elixir Weekly", base_url: "https://elixirweekly.net"})

      matching =
        article_fixture(user, feed, %{
          title: "Phoenix LiveView 1.1",
          content_html: "<p>Streams!</p>"
        })

      _non_matching = article_fixture(user, feed, %{title: "Rails News"})

      assert [%Article{id: id}] = Reader.list_articles_for_user(user, search: "liveview")
      assert id == matching.id

      article_ids =
        Reader.list_articles_for_user(user, search: "elixirweekly")
        |> Enum.map(& &1.id)

      assert matching.id in article_ids
    end

    test "list_articles_for_user/2 searches across content and feed site URL with FTS5" do
      user = user_fixture()

      feed =
        feed_fixture(user, %{
          title: "Systems Blog",
          site_url: "https://systems.example.com",
          base_url: "https://systems.example.com"
        })

      matching =
        article_fixture(user, feed, %{
          title: "Deep Dive",
          content_html: "<p>Distributed systems and message queues</p>"
        })

      _non_matching = article_fixture(user, feed, %{title: "Gardening Notes"})

      assert [%Article{id: content_match_id} | _rest] =
               Reader.list_articles_for_user(user, search: "message")

      assert content_match_id == matching.id

      article_ids =
        Reader.list_articles_for_user(user, search: "systems.example.com")
        |> Enum.map(& &1.id)

      assert matching.id in article_ids
    end

    test "list_articles_for_user/2 falls back to LIKE when FTS table is unavailable" do
      user = user_fixture()
      feed = feed_fixture(user)

      matching =
        article_fixture(user, feed, %{
          title: "Fallback Search Path",
          content_html: "<p>Safe fallback behavior</p>"
        })

      Repo.query!("DROP TABLE articles_search")

      assert [%Article{id: id}] = Reader.list_articles_for_user(user, search: "fallback")
      assert id == matching.id
    end

    test "mark_article_read/1 and mark_all_read_for_user/2 update read state" do
      user = user_fixture()
      feed = feed_fixture(user)
      article_a = article_fixture(user, feed, %{is_read: false})
      article_b = article_fixture(user, feed, %{is_read: false})

      assert {:ok, %Article{} = updated_article} = Reader.mark_article_read(article_a)
      assert updated_article.is_read

      assert 1 == Reader.mark_all_read_for_user(user, feed_id: feed.id, filter: :unread)

      assert Reader.get_article_for_user!(user, article_b.id).is_read
    end

    test "feed_unread_counts/1 and unread_count_for_user/1 return expected counts" do
      user = user_fixture()
      feed_a = feed_fixture(user)
      feed_b = feed_fixture(user)

      _ = article_fixture(user, feed_a, %{is_read: false})
      _ = article_fixture(user, feed_a, %{is_read: false})
      _ = article_fixture(user, feed_b, %{is_read: false})
      _ = article_fixture(user, feed_b, %{is_read: true})

      assert Reader.unread_count_for_user(user) == 3

      counts = Reader.feed_unread_counts(user)
      assert counts[feed_a.id] == 2
      assert counts[feed_b.id] == 1
    end

    test "user-scoped article queries do not leak data across users" do
      user_a = user_fixture()
      user_b = user_fixture()
      feed_a = feed_fixture(user_a)
      feed_b = feed_fixture(user_b)
      article_a = article_fixture(user_a, feed_a, %{title: "User A only"})
      article_b = article_fixture(user_b, feed_b, %{title: "User B only"})

      article_ids_for_user_a =
        Reader.list_articles_for_user(user_a, filter: :all)
        |> Enum.map(& &1.id)

      assert article_a.id in article_ids_for_user_a
      refute article_b.id in article_ids_for_user_a

      assert_raise Ecto.NoResultsError, fn ->
        Reader.get_article_for_user!(user_a, article_b.id)
      end
    end
  end

  describe "feed discovery and ingestion" do
    setup do
      original_source = Application.get_env(:icarurss, :feed_source)
      original_discover = Application.get_env(:icarurss, :feed_source_fake_discover)
      original_fetch = Application.get_env(:icarurss, :feed_source_fake_fetch_feed)

      Application.put_env(:icarurss, :feed_source, Icarurss.Reader.FeedSource.Fake)

      on_exit(fn ->
        Application.put_env(:icarurss, :feed_source, original_source)
        Application.put_env(:icarurss, :feed_source_fake_discover, original_discover)
        Application.put_env(:icarurss, :feed_source_fake_fetch_feed, original_fetch)
      end)

      :ok
    end

    test "discover_feed_candidates/1 delegates to configured feed source" do
      Application.put_env(
        :icarurss,
        :feed_source_fake_discover,
        {:ok, [%{feed_url: "https://a/feed.xml"}]}
      )

      assert {:ok, [%{feed_url: "https://a/feed.xml"}]} =
               Reader.discover_feed_candidates("https://a")
    end

    test "subscribe_feed_from_candidate/3 creates feed and imports initial entries as read" do
      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "Tech Feed",
           site_url: "https://tech.example.com",
           base_url: "https://tech.example.com",
           favicon_url: "https://tech.example.com/favicon.ico",
           entries: [
             %{
               guid: "g-1",
               url: "https://tech.example.com/a1",
               title: "Article A1",
               content_html: "<p>A1</p>",
               published_at: DateTime.utc_now(:second)
             },
             %{
               guid: "g-2",
               url: "https://tech.example.com/a2",
               title: "Article A2",
               content_html: "<p>A2</p>",
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      user = user_fixture()

      assert {:ok, feed, {:ok, stats}} =
               Reader.subscribe_feed_from_candidate(
                 user,
                 %{
                   feed_url: "https://tech.example.com/feed.xml",
                   title: "Tech Feed",
                   site_url: "https://tech.example.com",
                   base_url: "https://tech.example.com",
                   favicon_url: "https://tech.example.com/favicon.ico"
                 },
                 initial_mark_read: true
               )

      assert stats.inserted == 2
      assert stats.updated == 0

      articles = Reader.list_articles_for_user(user, feed_id: feed.id, filter: :all)
      assert length(articles) == 2
      assert Enum.all?(articles, & &1.is_read)
    end

    test "subscribe_feed_from_candidate/3 sanitizes imported HTML content" do
      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "Sanitized Feed",
           entries: [
             %{
               guid: "sanitized-1",
               url: "https://safe.example.com/a1",
               title: "Sanitized Entry",
               summary_html: ~s|<img src="x" onerror="alert(1)">|,
               content_html: ~s|<div><script>alert(1)</script><p onclick="x()">Hello</p></div>|,
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      user = user_fixture()

      assert {:ok, feed, {:ok, stats}} =
               Reader.subscribe_feed_from_candidate(
                 user,
                 %{
                   feed_url: "https://safe.example.com/feed.xml",
                   title: "Sanitized Feed"
                 }
               )

      assert stats.inserted == 1

      [article] = Reader.list_articles_for_user(user, feed_id: feed.id, filter: :all)

      refute String.contains?(article.summary_html || "", "onerror")
      refute String.contains?(article.content_html || "", "<script")
      refute String.contains?(article.content_html || "", "onclick")
      assert String.contains?(article.content_html || "", "Hello")
    end

    test "refresh_user_feeds/2 refreshes all user feeds and imports unread entries by default" do
      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        fn feed_url ->
          {:ok,
           %{
             title: "Feed for #{feed_url}",
             entries: [
               %{
                 guid: "guid-#{feed_url}",
                 url: "https://example.com/#{:erlang.phash2(feed_url)}",
                 title: "Fresh for #{feed_url}",
                 published_at: DateTime.utc_now(:second)
               }
             ]
           }}
        end
      )

      user = user_fixture()
      _feed_a = feed_fixture(user, %{feed_url: "https://feeds.example.com/a.xml"})
      _feed_b = feed_fixture(user, %{feed_url: "https://feeds.example.com/b.xml"})

      stats = Reader.refresh_user_feeds(user)

      assert stats.ok == 2
      assert stats.error == 0
      assert stats.inserted == 2

      articles = Reader.list_articles_for_user(user, filter: :all)
      assert Enum.any?(articles, fn article -> article.is_read == false end)
    end

    test "refresh_feed/2 deduplicates existing articles by guid and updates fields" do
      user = user_fixture()
      feed = feed_fixture(user, %{feed_url: "https://feeds.example.com/dedupe.xml"})

      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "Dedupe Feed",
           entries: [
             %{
               guid: "guid-dedupe-1",
               url: "https://feeds.example.com/posts/1",
               title: "Original title",
               content_html: "<p>v1</p>",
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      assert {:ok, first_stats} = Reader.refresh_feed(feed)
      assert first_stats.inserted == 1

      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "Dedupe Feed",
           entries: [
             %{
               guid: "guid-dedupe-1",
               url: "https://feeds.example.com/posts/1",
               title: "Updated title",
               content_html: "<p>v2</p>",
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      assert {:ok, second_stats} = Reader.refresh_feed(feed)
      assert second_stats.inserted == 0
      assert second_stats.updated == 1

      [article] = Reader.list_articles_for_user(user, filter: :all)
      assert article.title == "Updated title"
      assert article.content_html =~ "v2"
    end
  end

  describe "opml portability" do
    test "import_opml_for_user/2 creates folders and feeds while skipping duplicates" do
      user = user_fixture()
      _existing_feed = feed_fixture(user, %{feed_url: "https://dupe.example.com/feed.xml"})

      opml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
        <body>
          <outline text="Blogs" title="Blogs">
            <outline text="Duplicate" xmlUrl="https://dupe.example.com/feed.xml" htmlUrl="https://dupe.example.com" />
            <outline text="Blog Feed" xmlUrl="https://blogs.example.com/feed.xml" htmlUrl="https://blogs.example.com" />
          </outline>
          <outline text="Ungrouped Feed" xmlUrl="https://ungrouped.example.com/feed.xml" htmlUrl="https://ungrouped.example.com" />
        </body>
      </opml>
      """

      assert {:ok, stats} = Reader.import_opml_for_user(user, opml)
      assert stats.folders_created == 1
      assert stats.feeds_added == 2
      assert stats.feeds_skipped == 1

      [folder] = Reader.list_folders(user)
      assert folder.name == "Blogs"

      grouped_feed =
        Reader.list_feeds(user)
        |> Enum.find(&(&1.feed_url == "https://blogs.example.com/feed.xml"))

      ungrouped_feed =
        Reader.list_feeds(user)
        |> Enum.find(&(&1.feed_url == "https://ungrouped.example.com/feed.xml"))

      assert grouped_feed.folder_id == folder.id
      assert is_nil(ungrouped_feed.folder_id)
    end

    test "import_opml_for_user/2 returns an error for malformed OPML" do
      user = user_fixture()

      assert {:error, "Could not parse OPML document"} =
               Reader.import_opml_for_user(user, "<opml")
    end

    test "export_opml_for_user/1 exports grouped and ungrouped subscriptions" do
      user = user_fixture()
      folder = folder_fixture(user, %{name: "Podcasts", position: 0})

      _grouped_feed =
        feed_fixture(user, %{folder_id: folder.id, feed_url: "https://pod.example.com/feed"})

      _ungrouped_feed =
        feed_fixture(user, %{folder_id: nil, feed_url: "https://news.example.com/feed"})

      assert {:ok, opml_xml} = Reader.export_opml_for_user(user)
      assert String.contains?(opml_xml, "<opml version=\"2.0\">")
      assert String.contains?(opml_xml, "Podcasts")
      assert String.contains?(opml_xml, "https://pod.example.com/feed")
      assert String.contains?(opml_xml, "https://news.example.com/feed")

      assert {:ok, entries} = Opml.parse(opml_xml)

      assert Enum.any?(entries, fn entry ->
               entry.feed_url == "https://pod.example.com/feed" and
                 entry.folder_name == "Podcasts"
             end)

      assert Enum.any?(entries, fn entry ->
               entry.feed_url == "https://news.example.com/feed" and
                 is_nil(entry.folder_name)
             end)
    end
  end
end
