defmodule Icarurss.Repo.Migrations.CreateReaderTables do
  use Ecto.Migration

  def change do
    create table(:folders) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0
      add :expanded, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:folders, [:user_id])
    create unique_index(:folders, [:user_id, :name])

    create table(:feeds) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :folder_id, references(:folders, on_delete: :nilify_all)
      add :title, :string
      add :site_url, :string
      add :feed_url, :string, null: false
      add :base_url, :string
      add :favicon_url, :string
      add :last_fetched_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:feeds, [:user_id])
    create index(:feeds, [:folder_id])
    create unique_index(:feeds, [:user_id, :feed_url])

    create table(:articles) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :feed_id, references(:feeds, on_delete: :delete_all), null: false
      add :guid, :string
      add :url, :string
      add :title, :string, null: false
      add :author, :string
      add :summary_html, :text
      add :content_html, :text
      add :published_at, :utc_datetime
      add :fetched_at, :utc_datetime
      add :is_read, :boolean, null: false, default: false
      add :is_starred, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:articles, [:user_id])
    create index(:articles, [:feed_id])
    create index(:articles, [:user_id, :is_read])
    create index(:articles, [:user_id, :is_starred])
    create index(:articles, [:user_id, :published_at])
    create unique_index(:articles, [:user_id, :feed_id, :guid], where: "guid IS NOT NULL")
    create unique_index(:articles, [:user_id, :feed_id, :url], where: "url IS NOT NULL")
  end
end
