defmodule IcarurssWeb.FeedSettingsControllerTest do
  use IcarurssWeb.ConnCase

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader

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

      assert Enum.any?(Reader.list_feeds(user), &(&1.feed_url == "https://hnrss.org/frontpage"))
      assert Enum.any?(Reader.list_folders(user), &(&1.name == "Tech"))
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
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Could not import OPML file."
    end
  end
end
