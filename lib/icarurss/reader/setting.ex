defmodule Icarurss.Reader.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  alias Icarurss.Accounts.User

  schema "reader_settings" do
    field :timezone, :string, default: "UTC"
    field :article_open_mode, Ecto.Enum, values: [:three_column, :new_tab], default: :three_column

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:user_id, :timezone, :article_open_mode])
    |> validate_required([:user_id, :timezone, :article_open_mode])
    |> validate_length(:timezone, min: 2, max: 100)
    |> validate_timezone()
    |> unique_constraint(:user_id)
  end

  defp validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, timezone ->
      case DateTime.now(timezone) do
        {:ok, _datetime} -> []
        _ -> [timezone: "is not a valid IANA timezone"]
      end
    end)
  end
end
