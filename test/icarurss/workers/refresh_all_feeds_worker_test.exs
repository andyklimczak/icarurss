defmodule Icarurss.Workers.RefreshAllFeedsWorkerTest do
  use Icarurss.DataCase, async: false
  use Oban.Testing, repo: Icarurss.Repo

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader
  alias Icarurss.Workers.RefreshAllFeedsWorker

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

  test "perform/1 enqueues per-feed refresh jobs" do
    user = user_fixture()
    feed_a = feed_fixture(user, %{feed_url: "https://feeds.example.com/a.xml"})
    feed_b = feed_fixture(user, %{feed_url: "https://feeds.example.com/b.xml"})

    assert :ok = perform_job(RefreshAllFeedsWorker, %{})

    assert_enqueued(
      worker: Icarurss.Workers.RefreshFeedWorker,
      queue: :feed_refresh,
      args: %{feed_id: feed_a.id}
    )

    assert_enqueued(
      worker: Icarurss.Workers.RefreshFeedWorker,
      queue: :feed_refresh,
      args: %{feed_id: feed_b.id}
    )

    assert Reader.list_articles_for_user(user, filter: :all) == []
  end
end
