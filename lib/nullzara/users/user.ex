defmodule Nullzara.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :uuid, Ecto.UUID, autogenerate: true
    field :name, :string
    field :token_hash, :string
    field :mnemonic_hash, :string
    field :raw_token, :string, virtual: true
    field :raw_login_token, :string, virtual: true

    has_many :webauthn_credentials, Nullzara.Webauthn.Credential
    has_one :wallet_credential, Nullzara.Wallet.Credential

    timestamps(type: :utc_datetime)
  end

  def slug(%__MODULE__{mnemonic_hash: hash}) when is_binary(hash), do: generate_slug(hash)

  # Magic-link accounts have no mnemonic. Seed from the UUID, which never
  # changes, so regenerating the login token keeps the same slug.
  def slug(%__MODULE__{mnemonic_hash: nil, uuid: uuid}) when is_binary(uuid),
    do: generate_slug(uuid)

  # UniqueNamesGenerator raises for roughly 1 in 1000 seeds. Those accounts
  # would crash every page that shows the slug, so fall back to the same
  # seed with a suffix, which is just as stable.
  defp generate_slug(seed, attempt \\ 0) do
    UniqueNamesGenerator.generate([:adjectives, :animals, :names],
      seed: if(attempt == 0, do: seed, else: "#{seed}:#{attempt}"),
      separator: "-"
    )
  rescue
    error in [ArgumentError, MatchError] ->
      if attempt < 10, do: generate_slug(seed, attempt + 1), else: reraise(error, __STACKTRACE__)
  end

  def is_magiclink?(%__MODULE__{mnemonic_hash: nil}), do: true
  def is_magiclink?(%__MODULE__{}), do: false

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
    # Count code points, as Postgres does, so no name can overflow the column.
    |> validate_length(:name, max: 50, count: :codepoints)
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
  def magiclink_changeset(user, attrs) do
    raw_login_token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    login_hash = hash_token(raw_login_token)

    user
    |> changeset(attrs)
    |> put_change(:token_hash, login_hash)
    |> put_change(:raw_login_token, raw_login_token)
    |> unique_constraint(:token_hash)
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

defimpl Phoenix.Param, for: Nullzara.Users.User do
  def to_param(%{mnemonic_hash: nil, raw_login_token: token}) when is_binary(token), do: token
  def to_param(%{uuid: uuid}), do: uuid
end
