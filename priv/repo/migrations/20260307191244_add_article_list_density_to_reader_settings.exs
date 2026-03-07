defmodule Icarurss.Repo.Migrations.AddArticleListDensityToReaderSettings do
  use Ecto.Migration

  def change do
    alter table(:reader_settings) do
      add :article_list_density, :string, null: false, default: "comfortable"
    end
  end
end
