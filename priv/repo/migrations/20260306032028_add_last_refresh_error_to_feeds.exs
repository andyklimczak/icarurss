defmodule Icarurss.Repo.Migrations.AddLastRefreshErrorToFeeds do
  use Ecto.Migration

  def change do
    alter table(:feeds) do
      add :last_refresh_error, :string
    end
  end
end
