defmodule Icarurss.Workers.RefreshAllFeedsWorkerTest do
  use Icarurss.DataCase, async: false
  use Oban.Testing, repo: Icarurss.Repo

  import Icarurss.AccountsFixtures
  import Icarurss.ReaderFixtures

  alias Icarurss.Reader
  alias Icarurss.Workers.RefreshFeedWorker
  alias Icarurss.Workers.RefreshAllFeedsWorker

  setup do
    original_source = Application.get_env(:icarurss, :feed_source)
    original_fetch = Application.get_env(:icarurss, :feed_source_fake_fetch_feed)
    original_refresh = Application.get_env(:icarurss, :feed_refresh, [])

    Application.put_env(:icarurss, :feed_source, Icarurss.Reader.FeedSource.Fake)
    Application.put_env(:icarurss, :feed_refresh, max_concurrency: 1, spread_window_seconds: 30)

    on_exit(fn ->
      Application.put_env(:icarurss, :feed_source, original_source)
      Application.put_env(:icarurss, :feed_source_fake_fetch_feed, original_fetch)
      Application.put_env(:icarurss, :feed_refresh, original_refresh)
    end)

    :ok
  end

  test "perform/1 enqueues staggered feed refresh jobs by default" do
    user = user_fixture()

    feed_a = feed_fixture(user, %{feed_url: "https://feeds.example.com/a.xml"})
    feed_b = feed_fixture(user, %{feed_url: "https://feeds.example.com/b.xml"})
    feed_c = feed_fixture(user, %{feed_url: "https://feeds.example.com/c.xml"})

    assert :ok = perform_job(RefreshAllFeedsWorker, %{})

    jobs =
      all_enqueued(worker: RefreshFeedWorker, queue: :feed_refresh)
      |> Enum.sort_by(&DateTime.to_unix(&1.scheduled_at, :second))

    assert Enum.map(jobs, & &1.args["feed_id"]) == [feed_a.id, feed_b.id, feed_c.id]
    assert length(Reader.list_articles_for_user(user, filter: :all)) == 0

    [first, second, third] = jobs

    assert DateTime.compare(second.scheduled_at, first.scheduled_at) == :gt
    assert DateTime.compare(third.scheduled_at, second.scheduled_at) == :gt
    assert DateTime.diff(third.scheduled_at, first.scheduled_at, :second) <= 30
  end

  test "perform/1 refreshes feeds directly when spread is disabled" do
    user = user_fixture()

    _feed_a = feed_fixture(user, %{feed_url: "https://feeds.example.com/a.xml"})
    _feed_b = feed_fixture(user, %{feed_url: "https://feeds.example.com/b.xml"})

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

    assert :ok = perform_job(RefreshAllFeedsWorker, %{spread: false})

    assert length(Reader.list_articles_for_user(user, filter: :all)) == 2
    refute_enqueued(worker: RefreshFeedWorker, queue: :feed_refresh)
  end
end
