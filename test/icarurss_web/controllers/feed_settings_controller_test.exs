defmodule IcarurssWeb.FeedSettingsControllerTest do
  use IcarurssWeb.ConnCase
  use Oban.Testing, repo: Icarurss.Repo

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader
  alias Icarurss.Workers.RefreshFeedWorker

  setup do
    original_dev_routes = Application.get_env(:icarurss, :dev_routes, false)

    on_exit(fn ->
      Application.put_env(:icarurss, :dev_routes, original_dev_routes)
    end)

    :ok
  end

  describe "GET /users/settings/opml/export" do
    test "exports OPML for the current user", %{conn: conn} do
      user = user_fixture()
      folder = folder_fixture(user, %{name: "Tech"})

      _feed =
        feed_fixture(user, %{folder_id: folder.id, feed_url: "https://example.com/feed.xml"})

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/settings/opml/export")

      assert response(conn, 200) =~ "<opml"
      assert response(conn, 200) =~ "https://example.com/feed.xml"

      assert get_resp_header(conn, "content-type")
             |> Enum.any?(&String.contains?(&1, "text/x-opml"))

      assert get_resp_header(conn, "content-disposition")
             |> Enum.any?(&String.contains?(&1, ".opml"))
    end
  end

  describe "POST /users/settings/opml/import" do
    test "imports feeds from uploaded OPML", %{conn: conn} do
      user = user_fixture()

      path =
        Path.join(System.tmp_dir!(), "icarurss-import-#{System.unique_integer([:positive])}.opml")

      on_exit(fn -> File.rm(path) end)

      File.write!(
        path,
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
          <head><title>Icarurss Export</title></head>
          <body>
            <outline text="Tech">
              <outline type="rss" text="HNRSS" title="HNRSS" xmlUrl="https://hnrss.org/frontpage" htmlUrl="https://news.ycombinator.com/" />
            </outline>
          </body>
        </opml>
        """
      )

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/settings/opml/import", %{
          "import_opml" => %{
            "opml" => %Plug.Upload{
              path: path,
              filename: "feeds.opml",
              content_type: "text/x-opml"
            }
          }
        })

      assert redirected_to(conn) == ~p"/users/settings/opml"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Import complete"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "1 initial refresh queued"

      imported_feed =
        Enum.find(Reader.list_feeds(user), &(&1.feed_url == "https://hnrss.org/frontpage"))

      assert imported_feed
      assert Enum.any?(Reader.list_folders(user), &(&1.name == "Tech"))

      assert_enqueued(
        worker: RefreshFeedWorker,
        queue: :feed_refresh,
        args: %{feed_id: imported_feed.id}
      )
    end

    test "shows error for malformed OPML upload", %{conn: conn} do
      user = user_fixture()

      path =
        Path.join(
          System.tmp_dir!(),
          "icarurss-import-bad-#{System.unique_integer([:positive])}.opml"
        )

      on_exit(fn -> File.rm(path) end)

      File.write!(path, "<opml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/settings/opml/import", %{
          "import_opml" => %{
            "opml" => %Plug.Upload{
              path: path,
              filename: "broken.opml",
              content_type: "text/x-opml"
            }
          }
        })

      assert redirected_to(conn) == ~p"/users/settings/opml"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Could not import OPML file: Could not parse OPML document:"
    end
  end

  describe "POST /users/settings/opml/reset" do
    test "deletes only the current user's feeds and articles when development reset is enabled",
         %{
           conn: conn
         } do
      Application.put_env(:icarurss, :dev_routes, true)

      user = user_fixture()
      other_user = user_fixture()

      user_feed = feed_fixture(user)
      other_feed = feed_fixture(other_user)

      _user_article = article_fixture(user, user_feed)
      _other_article = article_fixture(other_user, other_feed)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/settings/opml/reset")

      assert redirected_to(conn) == ~p"/users/settings/opml"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Development reset complete: 1 feeds and 1 articles deleted."

      assert Reader.list_feeds(user) == []
      assert Reader.list_articles_for_user(user, filter: :all) == []
      assert length(Reader.list_feeds(other_user)) == 1
      assert length(Reader.list_articles_for_user(other_user, filter: :all)) == 1
    end

    test "returns not found when development reset is disabled", %{conn: conn} do
      Application.put_env(:icarurss, :dev_routes, false)

      user = user_fixture()
      feed = feed_fixture(user)
      _article = article_fixture(user, feed)

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/settings/opml/reset")

      assert response(conn, 404) == "Not Found"
      assert length(Reader.list_feeds(user)) == 1
      assert length(Reader.list_articles_for_user(user, filter: :all)) == 1
    end
  end
end
