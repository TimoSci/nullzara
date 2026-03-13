defmodule Nullzara.UsersTest do
  use Nullzara.DataCase

  alias Nullzara.Users

  describe "users" do
    alias Nullzara.Users.User

    import Nullzara.UsersFixtures

    @invalid_attrs %{name: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Users.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Users.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %User{} = user} = Users.create_user(valid_attrs)
      assert user.name == "some name"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Users.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %User{} = user} = Users.update_user(user, update_attrs)
      assert user.name == "some updated name"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Users.update_user(user, @invalid_attrs)
      assert user == Users.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Users.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Users.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Users.change_user(user)
    end

    test "get_user_by_token/1 finds user by login token" do
      {_user, _mnemonic_token, login_token} = user_fixture_with_token()
      assert {:ok, _user, :token} = Users.get_user_by_token(login_token)
    end

    test "get_user_by_token/1 finds user by mnemonic token" do
      {_user, mnemonic_token, _login_token} = user_fixture_with_token()
      assert {:ok, _user, :mnemonic} = Users.get_user_by_token(mnemonic_token)
    end

    test "get_user_by_token/1 returns error for unknown token" do
      assert {:error, :not_found} =
               Users.get_user_by_token("deadbeef" <> String.duplicate("0", 24))
    end

    test "regenerate_login_token/1 generates a new login token" do
      {user, _mnemonic_token, old_login_token} = user_fixture_with_token()
      old_hash = user.token_hash

      assert {:ok, updated_user} = Users.regenerate_login_token(user)
      assert updated_user.raw_login_token
      assert updated_user.raw_login_token != old_login_token
      assert updated_user.token_hash != old_hash
      assert updated_user.mnemonic_hash == user.mnemonic_hash
    end

    test "regenerate_login_token/1 invalidates old login token" do
      {user, _mnemonic_token, old_login_token} = user_fixture_with_token()

      {:ok, _updated_user} = Users.regenerate_login_token(user)
      assert {:error, :not_found} = Users.get_user_by_token(old_login_token)
    end

    test "regenerate_login_token/1 preserves mnemonic access" do
      {user, mnemonic_token, _login_token} = user_fixture_with_token()

      {:ok, _updated_user} = Users.regenerate_login_token(user)
      assert {:ok, _user, :mnemonic} = Users.get_user_by_token(mnemonic_token)
    end
  end
end
