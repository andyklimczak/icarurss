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

  test "perform/1 refreshes feeds directly" do
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

    assert :ok = perform_job(RefreshAllFeedsWorker, %{})

    assert length(Reader.list_articles_for_user(user, filter: :all)) == 2
  end
end
