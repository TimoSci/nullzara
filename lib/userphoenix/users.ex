defmodule Userphoenix.Users do
  @moduledoc """
  The Users context.
  """

  import Ecto.Query, warn: false
  alias Userphoenix.Repo

  alias Userphoenix.Users.User

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
