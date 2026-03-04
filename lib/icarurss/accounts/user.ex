defmodule Icarurss.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Icarurss.Reader.{Article, Feed, Folder, Setting}

  schema "users" do
    field :username, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :password, :string, virtual: true, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    has_many :folders, Folder
    has_many :feeds, Feed
    has_many :articles, Article
    has_one :reader_setting, Setting

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :username])
    |> validate_email(opts)
    |> validate_username(opts, required?: false)
    |> validate_required([:role])
  end

  @doc """
  A user changeset for changing username.
  """
  def username_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username])
    |> normalize_username()
    |> validate_username(opts, required?: true)
  end

  @doc """
  A user changeset for registering with username and password.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> normalize_username()
    |> validate_username(opts, required?: true)
    |> maybe_put_default_email_from_username()
    |> validate_email(opts)
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
    |> validate_required([:role])
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Icarurss.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_username(changeset, opts, validation_opts) do
    required? = Keyword.get(validation_opts, :required?, true)

    changeset =
      if required? do
        validate_required(changeset, [:username])
      else
        changeset
      end

    changeset =
      changeset
      |> validate_length(:username, min: 3, max: 40)
      |> validate_format(:username, ~r/^[a-z0-9_]+$/,
        message: "must contain only lowercase letters, numbers, and underscores"
      )

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Icarurss.Repo)
      |> unique_constraint(:username)
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password, :current_password])
    |> maybe_validate_current_password(user, opts)
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_current_password(changeset, user, opts) do
    if Keyword.get(opts, :require_current_password, false) do
      changeset
      |> validate_required([:current_password])
      |> validate_current_password(user)
    else
      changeset
    end
  end

  defp validate_current_password(changeset, user) do
    current_password = get_change(changeset, :current_password)

    cond do
      not (is_binary(current_password) and current_password != "") ->
        changeset

      valid_password?(user, current_password) ->
        changeset

      true ->
        add_error(changeset, :current_password, "is not valid")
    end
  end

  defp normalize_username(changeset) do
    update_change(changeset, :username, fn username ->
      username
      |> to_string()
      |> String.trim()
      |> String.downcase()
    end)
  end

  defp maybe_put_default_email_from_username(changeset) do
    username = get_field(changeset, :username)
    email = get_field(changeset, :email)

    if is_binary(username) and String.trim(username) != "" and (is_nil(email) or email == "") do
      put_change(changeset, :email, "#{username}@local.invalid")
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Updates a user's role for administrative operations.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Icarurss.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
