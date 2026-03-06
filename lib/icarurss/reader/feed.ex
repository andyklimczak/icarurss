defmodule Icarurss.Reader.Feed do
  use Ecto.Schema
  import Ecto.Changeset

  alias Icarurss.Accounts.User
  alias Icarurss.Reader.{Article, Folder}

  schema "feeds" do
    field :title, :string
    field :site_url, :string
    field :feed_url, :string
    field :base_url, :string
    field :favicon_url, :string
    field :last_fetched_at, :utc_datetime
    field :last_refresh_error, :string

    belongs_to :user, User
    belongs_to :folder, Folder
    has_many :articles, Article

    timestamps(type: :utc_datetime)
  end

  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :folder_id,
      :title,
      :site_url,
      :feed_url,
      :base_url,
      :favicon_url,
      :last_fetched_at,
      :last_refresh_error
    ])
    |> validate_required([:feed_url, :user_id])
    |> validate_format(:feed_url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> validate_length(:feed_url, max: 2048)
    |> validate_length(:title, max: 255)
    |> validate_length(:site_url, max: 2048)
    |> validate_length(:base_url, max: 2048)
    |> validate_length(:favicon_url, max: 2048)
    |> validate_length(:last_refresh_error, max: 500)
    |> unique_constraint([:user_id, :feed_url])
    |> assoc_constraint(:folder)
  end
end
