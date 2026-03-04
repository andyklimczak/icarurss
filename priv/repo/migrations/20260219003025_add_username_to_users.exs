defmodule Icarurss.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :username, :string, collate: :nocase
    end

    execute("""
    UPDATE users
    SET username = 'user_' || id
    WHERE username IS NULL OR trim(username) = '';
    """)

    create unique_index(:users, [:username])
  end

  def down do
    drop_if_exists unique_index(:users, [:username])

    alter table(:users) do
      remove :username
    end
  end
end
