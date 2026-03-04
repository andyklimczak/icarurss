defmodule Icarurss.Repo.Migrations.CreateReaderSettings do
  use Ecto.Migration

  def change do
    create table(:reader_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timezone, :string, null: false, default: "UTC"
      add :article_open_mode, :string, null: false, default: "three_column"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:reader_settings, [:user_id])
  end
end
