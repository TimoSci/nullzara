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

    test "update_user/2 rejects a name longer than 50 characters" do
      user = user_fixture()
      assert {:error, changeset} = Users.update_user(user, %{name: String.duplicate("a", 51)})
      assert "should be at most 50 character(s)" in errors_on(changeset).name
    end

    test "update_user/2 accepts 50 characters, including multi-byte ones" do
      user = user_fixture()
      assert {:ok, _} = Users.update_user(user, %{name: String.duplicate("a", 50)})
      assert {:ok, _} = Users.update_user(user, %{name: String.duplicate("🙂", 50)})
    end

    test "a magic-link user's slug survives regenerating the login token" do
      {:ok, user} = Users.create_magiclink_user(%{name: "m"})
      {:ok, updated} = Users.regenerate_login_token(user)

      assert User.slug(updated) == User.slug(user)
    end

    # The name generator raises for roughly 1 in 1000 seeds; this is one.
    @crashing_seed "5109faf2-3419-4e5c-b54a-98b475bc86d9"

    test "slug/1 still returns a stable name for a seed the generator cannot handle" do
      magiclink = %User{mnemonic_hash: nil, uuid: @crashing_seed}
      mnemonic = %User{mnemonic_hash: @crashing_seed}

      for user <- [magiclink, mnemonic] do
        slug = User.slug(user)
        assert slug =~ ~r/\A[^-]+-[^-]+-[^-]+\z/
        assert User.slug(user) == slug
      end
    end

    test "different magic-link users get different slugs" do
      {:ok, one} = Users.create_magiclink_user(%{name: "m"})
      {:ok, two} = Users.create_magiclink_user(%{name: "m"})

      refute User.slug(one) == User.slug(two)
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

  describe "admin?/1" do
    import Nullzara.UsersFixtures

    setup do
      previous = Application.get_env(:nullzara, :admin_uuids, [])
      on_exit(fn -> Application.put_env(:nullzara, :admin_uuids, previous) end)
      :ok
    end

    test "is true only for users whose UUID is configured" do
      admin = user_fixture()
      other = user_fixture()
      Application.put_env(:nullzara, :admin_uuids, [admin.uuid])

      assert Nullzara.Users.admin?(admin)
      refute Nullzara.Users.admin?(other)
    end

    test "is false for everyone when no admins are configured" do
      Application.put_env(:nullzara, :admin_uuids, [])

      refute Nullzara.Users.admin?(user_fixture())
      refute Nullzara.Users.admin?(nil)
    end
  end

  describe "parse_admin_uuids/1" do
    test "splits a comma-separated list, trimming blanks and normalising case" do
      assert Nullzara.Users.parse_admin_uuids(
               " 486CD7FE-5521-421F-A591-219103C0830C ,, 5f3ae4f5-d40b-422e-916c-3969c86fadce "
             ) == [
               "486cd7fe-5521-421f-a591-219103c0830c",
               "5f3ae4f5-d40b-422e-916c-3969c86fadce"
             ]
    end

    test "returns an empty list for nil or an empty string" do
      assert Nullzara.Users.parse_admin_uuids(nil) == []
      assert Nullzara.Users.parse_admin_uuids("") == []
    end

    test "raises on an entry that is not a UUID" do
      assert_raise ArgumentError, ~r/ADMIN_UUIDS/, fn ->
        Nullzara.Users.parse_admin_uuids("not-a-uuid")
      end
    end
  end
end
