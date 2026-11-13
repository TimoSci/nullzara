defmodule Nullzara.Users do
  @moduledoc """
  The Users context.
  """

  import Ecto.Query, warn: false
  alias Nullzara.Repo

  alias Nullzara.Users.User

  @doc """
  Returns the list of users.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user by UUID.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user_by_uuid!(uuid), do: Repo.get_by!(User, uuid: uuid)

  @doc """
  Gets a single user by id. Returns nil if not found.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Returns true if the user is an admin.

  Admins are the accounts whose UUID is listed in the `ADMIN_UUIDS`
  environment variable (see `parse_admin_uuids/1`). With no admins
  configured, nobody is an admin.
  """
  def admin?(%User{uuid: uuid}) when is_binary(uuid) do
    uuid in Application.get_env(:nullzara, :admin_uuids, [])
  end

  def admin?(_), do: false

  @doc """
  Parses the comma-separated `ADMIN_UUIDS` value into a list of UUIDs.

  Raises `ArgumentError` on an entry that is not a UUID, so a typo fails
  at boot instead of silently leaving the app without that admin.
  """
  def parse_admin_uuids(nil), do: []

  def parse_admin_uuids(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn entry ->
      case Ecto.UUID.cast(entry) do
        {:ok, uuid} -> uuid
        :error -> raise ArgumentError, "ADMIN_UUIDS contains an invalid UUID: #{inspect(entry)}"
      end
    end)
  end

  @doc """
  Gets a user by raw token. Hashes the token and queries by token_hash or mnemonic_hash.

  Returns `{:ok, user, :token | :mnemonic}` or `{:error, :not_found}`.
  """
  def get_user_by_token(raw_token) do
    hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    query =
      from u in User,
        where: u.token_hash == ^hash or u.mnemonic_hash == ^hash

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      user ->
        match_type = if user.token_hash == hash, do: :token, else: :mnemonic
        {:ok, user, match_type}
    end
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a user with a generated access token.
  """
  def create_user_with_token(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a magiclink user with only a login token (no mnemonic hash).
  """
  def create_magiclink_user(attrs) do
    %User{}
    |> User.magiclink_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by raw login token. Only matches against token_hash.

  Returns `{:ok, user}` or `{:error, :not_found}`.
  """
  def get_user_by_login_token(raw_token) do
    hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    case Repo.get_by(User, token_hash: hash) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Regenerates the login token for a user.

  Returns `{:ok, user}` with `raw_login_token` populated.
  """
  def regenerate_login_token(%User{} = user) do
    user
    |> User.login_token_changeset()
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
