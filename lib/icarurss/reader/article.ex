defmodule Icarurss.Reader.Article do
  use Ecto.Schema
  import Ecto.Changeset

  alias Icarurss.Accounts.User
  alias Icarurss.Reader.Feed

  schema "articles" do
    field :guid, :string
    field :url, :string
    field :title, :string
    field :author, :string
    field :summary_html, :string
    field :content_html, :string
    field :published_at, :utc_datetime
    field :fetched_at, :utc_datetime
    field :is_read, :boolean, default: false
    field :is_starred, :boolean, default: false

    belongs_to :user, User
    belongs_to :feed, Feed

    timestamps(type: :utc_datetime)
  end

  def changeset(article, attrs) do
    article
    |> cast(attrs, [
      :guid,
      :url,
      :title,
      :author,
      :summary_html,
      :content_html,
      :published_at,
      :fetched_at,
      :is_read,
      :is_starred
    ])
    |> validate_required([:title, :user_id, :feed_id])
    |> validate_length(:title, min: 1, max: 500)
    |> validate_length(:guid, max: 1024)
    |> validate_length(:url, max: 2048)
    |> validate_length(:author, max: 255)
    |> validate_length(:summary_html, max: 1_000_000)
    |> validate_length(:content_html, max: 2_000_000)
    |> assoc_constraint(:feed)
    |> unique_constraint([:user_id, :feed_id, :guid], name: :articles_user_id_feed_id_guid_index)
    |> unique_constraint([:user_id, :feed_id, :url], name: :articles_user_id_feed_id_url_index)
  end
end
