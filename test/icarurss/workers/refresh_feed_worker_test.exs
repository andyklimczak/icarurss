defmodule Icarurss.Workers.RefreshFeedWorkerTest do
  use Icarurss.DataCase, async: false
  use Oban.Testing, repo: Icarurss.Repo

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader
  alias Icarurss.Reader.RefreshError
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
    assert is_nil(Reader.get_feed(feed.id).last_refresh_error)
  end

  test "perform/1 returns error when feed fetch fails" do
    user = user_fixture()
    feed = feed_fixture(user, %{feed_url: "https://feeds.example.com/main.xml"})

    Application.put_env(:icarurss, :feed_source_fake_fetch_feed, {:error, "upstream timeout"})

    assert {:error, %RefreshError{kind: :request, retryable?: true, message: "upstream timeout"}} =
             perform_job(RefreshFeedWorker, %{feed_id: feed.id})

    refreshed_feed = Reader.get_feed(feed.id)
    assert refreshed_feed.last_refresh_error == "upstream timeout"
    assert refreshed_feed.refresh_status == "transient_error"
    assert refreshed_feed.refresh_error_kind == "request"
    assert refreshed_feed.refresh_failure_count == 1
    assert %DateTime{} = refreshed_feed.next_refresh_after
  end

  test "perform/1 cancels permanent feed failures" do
    user = user_fixture()
    feed = feed_fixture(user, %{feed_url: "https://feeds.example.com/main.xml"})

    Application.put_env(
      :icarurss,
      :feed_source_fake_fetch_feed,
      {:error,
       RefreshError.new(:non_feed, "This URL does not appear to be a valid RSS/Atom feed",
         retryable?: false,
         permanent?: true
       )}
    )

    assert {:cancel, %RefreshError{kind: :non_feed, retryable?: false}} =
             perform_job(RefreshFeedWorker, %{feed_id: feed.id})

    refreshed_feed = Reader.get_feed(feed.id)
    assert refreshed_feed.refresh_status == "permanent_error"
    assert refreshed_feed.refresh_error_kind == "non_feed"
  end

  test "perform/1 clears persisted refresh errors after a successful retry" do
    user = user_fixture()

    feed =
      feed_fixture(user, %{
        feed_url: "https://feeds.example.com/main.xml",
        last_refresh_error: "upstream timeout"
      })

    Application.put_env(
      :icarurss,
      :feed_source_fake_fetch_feed,
      {:ok,
       %{
         title: "Recovered Feed",
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
    refreshed_feed = Reader.get_feed(feed.id)
    assert is_nil(refreshed_feed.last_refresh_error)
    assert refreshed_feed.refresh_status == "ok"
    assert refreshed_feed.refresh_failure_count == 0
    assert is_nil(refreshed_feed.next_refresh_after)
  end
end
