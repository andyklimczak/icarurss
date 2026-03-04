defmodule Icarurss.Reader.FeedSource do
  @moduledoc """
  Behaviour for discovering and fetching RSS/Atom feeds.
  """

  @type feed_candidate :: %{
          required(:feed_url) => String.t(),
          optional(:title) => String.t() | nil,
          optional(:site_url) => String.t() | nil,
          optional(:base_url) => String.t() | nil,
          optional(:favicon_url) => String.t() | nil
        }

  @type feed_entry :: %{
          optional(:guid) => String.t() | nil,
          optional(:url) => String.t() | nil,
          optional(:title) => String.t() | nil,
          optional(:author) => String.t() | nil,
          optional(:summary_html) => String.t() | nil,
          optional(:content_html) => String.t() | nil,
          optional(:published_at) => DateTime.t() | nil
        }

  @type feed_payload :: %{
          optional(:title) => String.t() | nil,
          optional(:site_url) => String.t() | nil,
          optional(:base_url) => String.t() | nil,
          optional(:favicon_url) => String.t() | nil,
          required(:entries) => [feed_entry()]
        }

  @callback discover(String.t()) :: {:ok, [feed_candidate()]} | {:error, String.t()}
  @callback fetch_feed(String.t()) :: {:ok, feed_payload()} | {:error, String.t()}
end
