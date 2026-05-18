defmodule Icarurss.Repo.Migrations.AddRefreshHealthToFeeds do
  use Ecto.Migration

  def change do
    alter table(:feeds) do
      add :refresh_status, :string, null: false, default: "ok"
      add :refresh_error_kind, :string
      add :refresh_failure_count, :integer, null: false, default: 0
      add :last_refresh_failed_at, :utc_datetime
      add :next_refresh_after, :utc_datetime
    end

    create index(:feeds, [:next_refresh_after])
  end
end
