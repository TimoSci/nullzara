defmodule Userphoenix.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Phoenix.Param, key: :uuid}

  schema "users" do
    field :uuid, Ecto.UUID, autogenerate: true
    field :name, :string
    field :token_hash, :string
    field :mnemonic_hash, :string
    field :raw_token, :string, virtual: true
    field :raw_login_token, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def slug(%__MODULE__{mnemonic_hash: hash}) when is_binary(hash) do
    UniqueNamesGenerator.generate([:adjectives, :animals, :names],
      seed: hash,
      separator: "-"
    )
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end

  @doc false
  def registration_changeset(user, attrs) do
    raw_mnemonic_token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    mnemonic_hash = hash_token(raw_mnemonic_token)

    raw_login_token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    login_hash = hash_token(raw_login_token)

    user
    |> changeset(attrs)
    |> put_change(:mnemonic_hash, mnemonic_hash)
    |> put_change(:token_hash, login_hash)
    |> put_change(:raw_token, raw_mnemonic_token)
    |> put_change(:raw_login_token, raw_login_token)
    |> unique_constraint(:token_hash)
    |> unique_constraint(:mnemonic_hash)
  end

  @doc false
  def login_token_changeset(user) do
    raw_login_token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    login_hash = hash_token(raw_login_token)

    user
    |> change()
    |> put_change(:token_hash, login_hash)
    |> put_change(:raw_login_token, raw_login_token)
    |> unique_constraint(:token_hash)
  end

  defp hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end
end
