defmodule Icarurss.Reader.Folder do
  use Ecto.Schema
  import Ecto.Changeset

  alias Icarurss.Accounts.User
  alias Icarurss.Reader.Feed

  schema "folders" do
    field :name, :string
    field :position, :integer, default: 0
    field :expanded, :boolean, default: true

    belongs_to :user, User
    has_many :feeds, Feed

    timestamps(type: :utc_datetime)
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :position, :expanded])
    |> validate_required([:name, :position, :expanded, :user_id])
    |> validate_length(:name, min: 1, max: 160)
    |> unique_constraint([:user_id, :name])
  end
end
