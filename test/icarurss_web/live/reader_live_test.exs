defmodule IcarurssWeb.ReaderLiveTest do
  use IcarurssWeb.ConnCase
  use Oban.Testing, repo: Icarurss.Repo

  import Phoenix.LiveViewTest
  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader

  describe "reader live view" do
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

    test "renders the reader shell for authenticated users", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      assert has_element?(view, "#add-feed-button")
      assert has_element?(view, "#refresh-feeds-button")
      assert has_element?(view, "#reader-search-input")
      assert has_element?(view, "#mark-visible-read-button")
      assert has_element?(view, "#sidebar-filter-unread")
      assert has_element?(view, "#articles")
      assert has_element?(view, "#article-reader")
    end

    test "selecting an article marks it as read", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)
      article = article_fixture(user, feed, %{is_read: false})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element(~s(button[phx-click="select_article"][phx-value-id="#{article.id}"]))
      |> render_click()

      assert Reader.get_article_for_user!(user, article.id).is_read
      assert has_element?(view, "#article-content")
    end

    test "overlay reader mode opens and dismisses article panel", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)
      article = article_fixture(user, feed, %{is_read: false})

      {:ok, _setting} =
        Reader.update_reader_setting(user, %{"article_open_mode" => "new_tab"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      refute has_element?(view, "#article-reader")
      refute has_element?(view, "#article-overlay")

      view
      |> element("#articles-#{article.id}")
      |> render_click()

      assert has_element?(view, "#article-overlay")
      assert has_element?(view, "#article-overlay-panel")
      assert has_element?(view, "#close-article-overlay-button")

      view
      |> element("#close-article-overlay-button")
      |> render_click()

      refute has_element?(view, "#article-overlay")
      refute has_element?(view, "#articles-#{article.id}")
    end

    test "renders article timestamps in the user's configured timezone", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)
      {:ok, _setting} = Reader.update_reader_setting(user, %{"timezone" => "America/New_York"})

      _article =
        article_fixture(user, feed, %{
          is_read: false,
          published_at: ~U[2026-01-15 15:00:00Z]
        })

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      assert html =~ "Jan 15, 2026 10:00 AM"
    end

    test "selecting a feed from unread keeps unread filter active", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)
      unread_article = article_fixture(user, feed, %{is_read: false})
      read_article = article_fixture(user, feed, %{is_read: true})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#sidebar-feed-#{feed.id}")
      |> render_click()

      assert has_element?(view, "#articles-#{unread_article.id}")
      refute has_element?(view, "#articles-#{read_article.id}")
    end

    test "selected unread article stays visible until another article is selected", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)
      first_article = article_fixture(user, feed, %{is_read: false})
      second_article = article_fixture(user, feed, %{is_read: false})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#articles-#{first_article.id}")
      |> render_click()

      assert Reader.get_article_for_user!(user, first_article.id).is_read
      assert has_element?(view, "#articles-#{first_article.id}")

      view
      |> element("#articles-#{second_article.id}")
      |> render_click()

      assert Reader.get_article_for_user!(user, second_article.id).is_read
      refute has_element?(view, "#articles-#{first_article.id}")
      assert has_element?(view, "#articles-#{second_article.id}")
    end

    test "mark all read applies to currently selected feed", %{conn: conn} do
      user = user_fixture()
      feed_a = feed_fixture(user)
      feed_b = feed_fixture(user)

      article_a1 = article_fixture(user, feed_a, %{is_read: false})
      article_a2 = article_fixture(user, feed_a, %{is_read: false})
      article_b = article_fixture(user, feed_b, %{is_read: false})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#sidebar-feed-#{feed_a.id}")
      |> render_click()

      view
      |> element("#mark-visible-read-button")
      |> render_click()

      assert Reader.get_article_for_user!(user, article_a1.id).is_read
      assert Reader.get_article_for_user!(user, article_a2.id).is_read
      refute Reader.get_article_for_user!(user, article_b.id).is_read
    end

    test "add feed modal discovers candidates and subscribes", %{conn: conn} do
      user = user_fixture()

      Application.put_env(
        :icarurss,
        :feed_source_fake_discover,
        {:ok,
         [
           %{
             feed_url: "https://news.example.com/feed.xml",
             title: "News Feed",
             site_url: "https://news.example.com",
             base_url: "https://news.example.com",
             favicon_url: "https://news.example.com/favicon.ico"
           }
         ]}
      )

      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "News Feed",
           site_url: "https://news.example.com",
           base_url: "https://news.example.com",
           favicon_url: "https://news.example.com/favicon.ico",
           entries: [
             %{
               guid: "news-1",
               url: "https://news.example.com/a1",
               title: "News One",
               content_html: "<p>News one</p>",
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#add-feed-button")
      |> render_click()

      assert has_element?(view, "#add-feed-modal")

      view
      |> form("#discover-feeds-form", add_feed: %{url: "https://news.example.com"})
      |> render_submit()

      assert has_element?(view, "#feed-candidate-0")

      view
      |> element("#subscribe-feed-0")
      |> render_click()

      refute has_element?(view, "#add-feed-modal")

      feeds = Reader.list_feeds(user)
      assert Enum.any?(feeds, &(&1.feed_url == "https://news.example.com/feed.xml"))

      assert length(Reader.list_articles_for_user(user, filter: :all)) == 1
    end

    test "refresh button enqueues background refresh job", %{conn: conn} do
      user = user_fixture()
      _feed = feed_fixture(user, %{feed_url: "https://feeds.example.com/main.xml"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#refresh-feeds-button")
      |> render_click()

      assert_enqueued(worker: Icarurss.Workers.RefreshAllFeedsWorker, queue: :feed_refresh)
      assert render(view) =~ "Feed refresh queued"
    end

    test "creates folders from the sidebar modal", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#open-new-folder-modal-button")
      |> render_click()

      view
      |> form("#new-folder-modal-form", new_folder: %{name: "Podcasts"})
      |> render_submit()

      folders = Reader.list_folders(user)
      assert Enum.any?(folders, &(&1.name == "Podcasts"))
    end

    test "add feed modal can assign new feed into an existing folder", %{conn: conn} do
      user = user_fixture()
      folder = folder_fixture(user, %{name: "News"})

      Application.put_env(
        :icarurss,
        :feed_source_fake_discover,
        {:ok,
         [
           %{
             feed_url: "https://news.example.com/feed.xml",
             title: "News Feed",
             site_url: "https://news.example.com",
             base_url: "https://news.example.com",
             favicon_url: "https://news.example.com/favicon.ico"
           }
         ]}
      )

      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "News Feed",
           entries: [
             %{
               guid: "news-folder-1",
               url: "https://news.example.com/a1",
               title: "News One",
               content_html: "<p>News one</p>",
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#add-feed-button")
      |> render_click()

      view
      |> form("#discover-feeds-form",
        add_feed: %{url: "https://news.example.com", folder_id: folder.id}
      )
      |> render_submit()

      view
      |> element("#subscribe-feed-0")
      |> render_click()

      feed =
        Enum.find(Reader.list_feeds(user), &(&1.feed_url == "https://news.example.com/feed.xml"))

      assert feed.folder_id == folder.id
    end

    test "add feed modal can create a folder before subscribing", %{conn: conn} do
      user = user_fixture()

      Application.put_env(
        :icarurss,
        :feed_source_fake_discover,
        {:ok,
         [
           %{
             feed_url: "https://dev.example.com/feed.xml",
             title: "Dev Feed",
             site_url: "https://dev.example.com",
             base_url: "https://dev.example.com",
             favicon_url: "https://dev.example.com/favicon.ico"
           }
         ]}
      )

      Application.put_env(
        :icarurss,
        :feed_source_fake_fetch_feed,
        {:ok,
         %{
           title: "Dev Feed",
           entries: [
             %{
               guid: "dev-folder-1",
               url: "https://dev.example.com/a1",
               title: "Dev One",
               content_html: "<p>Dev one</p>",
               published_at: DateTime.utc_now(:second)
             }
           ]
         }}
      )

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#add-feed-button")
      |> render_click()

      view
      |> element("#open-add-feed-folder-modal-button")
      |> render_click()

      assert has_element?(view, "#add-feed-folder-modal")

      view
      |> form("#add-feed-folder-modal-form", add_feed_new_folder: %{name: "Engineering"})
      |> render_submit()

      folder = Enum.find(Reader.list_folders(user), &(&1.name == "Engineering"))
      assert folder
      refute has_element?(view, "#add-feed-folder-modal")

      view
      |> form("#discover-feeds-form",
        add_feed: %{url: "https://dev.example.com", folder_id: folder.id}
      )
      |> render_submit()

      view
      |> element("#subscribe-feed-0")
      |> render_click()

      feed =
        Enum.find(Reader.list_feeds(user), &(&1.feed_url == "https://dev.example.com/feed.xml"))

      assert feed.folder_id == folder.id
    end

    test "moves a selected feed into a folder", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user, %{folder_id: nil})
      folder = folder_fixture(user, %{name: "Blogs"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#sidebar-feed-#{feed.id}")
      |> render_click()

      view
      |> form("#move-feed-form", move_feed: %{feed_id: feed.id, folder_id: folder.id})
      |> render_change()

      updated_feed = Reader.get_feed_for_user!(user, feed.id)
      assert updated_feed.folder_id == folder.id
    end

    test "unsubscribes selected feed after confirmation", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)
      _article = article_fixture(user, feed)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      view
      |> element("#sidebar-feed-#{feed.id}")
      |> render_click()

      view
      |> element("#unsubscribe-feed-button")
      |> render_click()

      assert render(view) =~ "Confirm Unsubscribe"

      view
      |> element("#unsubscribe-feed-button")
      |> render_click()

      assert Reader.list_feeds(user) == []
      assert Reader.list_articles_for_user(user, filter: :all) == []
    end

    test "reloads article list when feed refresh pubsub event is received", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/")

      article =
        article_fixture(user, feed, %{
          title: "Live Update Article",
          is_read: false
        })

      send(
        view.pid,
        {:feeds_refreshed, %{user_id: user.id, feed_id: feed.id, inserted: 1, updated: 0}}
      )

      _ = :sys.get_state(view.pid)

      assert render(view) =~ "Live Update Article"
      assert has_element?(view, "#articles-#{article.id}.bg-emerald-50")
    end
  end
end
