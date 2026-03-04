defmodule Icarurss.Workers.RefreshFeedWorkerTest do
  use Icarurss.DataCase, async: false
  use Oban.Testing, repo: Icarurss.Repo

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader
  alias Icarurss.Workers.RefreshFeedWorker

  setup do
    original_source = Application.get_env(:icarurss, :feed_source)
    original_fetch = Application.get_env(:icarurss, :feed_source_fake_fetch_feed)

    Application.put_env(:icarurss, :feed_source, Icarurss.Reader.FeedSource.Fake)

    on_exit(fn ->
      Application.put_env(:icarurss, :feed_source, original_source)
      Application.put_env(:icarurss, :feed_source_fake_fetch_feed, original_fetch)
    end)

    :ok
  end

  test "perform/1 refreshes a single feed and imports entries" do
    user = user_fixture()
    feed = feed_fixture(user, %{feed_url: "https://feeds.example.com/main.xml"})

    Application.put_env(
      :icarurss,
      :feed_source_fake_fetch_feed,
      {:ok,
       %{
         title: "Main Feed",
         entries: [
           %{
             guid: "guid-main-1",
             url: "https://feeds.example.com/posts/1",
             title: "Main Post 1",
             published_at: DateTime.utc_now(:second)
           }
         ]
       }}
    )

    assert :ok = perform_job(RefreshFeedWorker, %{feed_id: feed.id})
    assert length(Reader.list_articles_for_user(user, filter: :all)) == 1
  end

  test "perform/1 returns error when feed fetch fails" do
    user = user_fixture()
    feed = feed_fixture(user, %{feed_url: "https://feeds.example.com/main.xml"})

    Application.put_env(:icarurss, :feed_source_fake_fetch_feed, {:error, "upstream timeout"})

    assert {:error, "upstream timeout"} = perform_job(RefreshFeedWorker, %{feed_id: feed.id})
  end
end
