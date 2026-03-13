defmodule Nullzara.UsersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Nullzara.Users` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Nullzara.Users.create_user()

    user
  end

  @doc """
  Generate a user with access tokens. Returns `{user, raw_mnemonic_token, raw_login_token}`.
  """
  def user_fixture_with_token(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Nullzara.Users.create_user_with_token()

    {user, user.raw_token, user.raw_login_token}
  end
end
