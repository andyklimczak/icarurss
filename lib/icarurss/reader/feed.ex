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
    field :refresh_status, :string, default: "ok"
    field :refresh_error_kind, :string
    field :refresh_failure_count, :integer, default: 0
    field :last_refresh_failed_at, :utc_datetime
    field :next_refresh_after, :utc_datetime

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
      :last_refresh_error,
      :refresh_status,
      :refresh_error_kind,
      :refresh_failure_count,
      :last_refresh_failed_at,
      :next_refresh_after
    ])
    |> validate_required([:feed_url, :user_id])
    |> validate_inclusion(:refresh_status, ["ok", "transient_error", "permanent_error"])
    |> validate_format(:feed_url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> validate_length(:feed_url, max: 2048)
    |> validate_length(:title, max: 255)
    |> validate_length(:site_url, max: 2048)
    |> validate_length(:base_url, max: 2048)
    |> validate_length(:favicon_url, max: 2048)
    |> validate_length(:last_refresh_error, max: 500)
    |> validate_length(:refresh_error_kind, max: 64)
    |> validate_number(:refresh_failure_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :feed_url])
    |> assoc_constraint(:folder)
  end
end
