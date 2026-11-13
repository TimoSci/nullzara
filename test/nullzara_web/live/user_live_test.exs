defmodule NullzaraWeb.UserLiveTest do
  use NullzaraWeb.ConnCase

  import Phoenix.LiveViewTest
  import Nullzara.UsersFixtures

  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  defp create_user(_) do
    {user, _token, _login_token} = user_fixture_with_token()
    %{user: user}
  end

  defp authenticate(%{conn: conn, user: user}) do
    %{conn: log_in_user(conn, user)}
  end

  defp promote_to_admin(%{user: user}) do
    make_admin(user)
    :ok
  end

  describe "Index" do
    setup [:create_user, :authenticate, :promote_to_admin]

    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, ~p"/users")

      assert html =~ "Listing Users"
      assert html =~ user.name
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New User")
               |> render_click()
               |> follow_redirect(conn, ~p"/users/new")

      assert render(form_live) =~ "New User"

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#user-form", user: %{name: "new user"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      html = render(index_live)
      assert html =~ "User created"
      assert html =~ "Recovery phrase:"
    end

    test "updates user in listing", %{conn: conn, user: user} do
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#users-#{user.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/users/#{user}/edit")

      assert render(form_live) =~ "Edit User"

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#user-form", user: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/users")

      html = render(index_live)
      assert html =~ "User updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes user in listing", %{conn: conn, user: user} do
      {:ok, index_live, _html} = live(conn, ~p"/users")

      assert index_live |> element("#users-#{user.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#users-#{user.id}")
    end
  end

  describe "Show" do
    setup [:create_user, :authenticate, :promote_to_admin]

    test "displays user", %{conn: conn, user: user} do
      {:ok, _show_live, html} = live(conn, ~p"/users/#{user}")

      assert html =~ "Show User"
      assert html =~ user.name
    end

    test "updates user and returns to show", %{conn: conn, user: user} do
      {:ok, show_live, _html} = live(conn, ~p"/users/#{user}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/users/#{user}/edit?return_to=show")

      assert render(form_live) =~ "Edit User"

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#user-form", user: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/users/#{user}")

      html = render(show_live)
      assert html =~ "User updated successfully"
      assert html =~ "some updated name"
    end
  end

  describe "as a signed-in user who is not an admin" do
    setup [:create_user, :authenticate]

    setup do
      {other, _token, _login_token} = user_fixture_with_token(%{name: "other user"})
      %{other: other}
    end

    test "the user list is off limits", %{conn: conn, user: user} do
      assert {:error, {:redirect, %{to: to, flash: flash}}} = live(conn, ~p"/users")
      assert to == ~p"/user/#{user}/dashboard"
      assert flash["error"] =~ "not authorized"
    end

    test "creating users is off limits", %{conn: conn, user: user} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/new")
      assert to == ~p"/user/#{user}/dashboard"
    end

    test "editing another user is off limits", %{conn: conn, user: user, other: other} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/#{other}/edit")
      assert to == ~p"/user/#{user}/dashboard"
      assert Nullzara.Users.get_user!(other.id).name == "other user"
    end

    test "editing their own record through the admin form is off limits",
         %{conn: conn, user: user} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/#{user}/edit")
      assert to == ~p"/user/#{user}/dashboard"
    end

    test "viewing another user's record is off limits", %{conn: conn, user: user, other: other} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/#{other}")
      assert to == ~p"/user/#{user}/dashboard"
    end
  end

  describe "as a visitor who is not signed in" do
    setup [:create_user]

    test "the admin pages redirect to the token login", %{conn: conn, user: user} do
      for path <- [~p"/users", ~p"/users/new", ~p"/users/#{user}/edit", ~p"/users/#{user}"] do
        assert {:error, {:redirect, %{to: "/access/token"}}} = live(conn, path)
      end
    end

    test "being listed as an admin does not replace signing in", %{conn: conn, user: user} do
      make_admin(user)
      assert {:error, {:redirect, %{to: "/access/token"}}} = live(conn, ~p"/users")
    end
  end

  describe "magic link record page" do
    test "a magic link at /users/<token> redirects to the login link", %{conn: conn} do
      {:ok, user} = Nullzara.Users.create_magiclink_user(%{name: "magic user"})
      token = user.raw_login_token

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/#{token}")
      assert to == ~p"/u/#{token}"
    end

    test "following that redirect signs the holder in", %{conn: conn} do
      {:ok, user} = Nullzara.Users.create_magiclink_user(%{name: "magic user"})
      token = user.raw_login_token

      {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/#{token}")
      conn = get(conn, to)

      assert redirected_to(conn) == ~p"/user/#{token}/dashboard"
      assert get_session(conn, :user_id) == user.id
    end

    test "an admin opening /users/<magic token> sees the record and stays themselves",
         %{conn: conn} do
      {admin, _token, _login_token} = user_fixture_with_token(%{name: "the admin"})
      make_admin(admin)
      conn = log_in_user(conn, admin)
      {:ok, user} = Nullzara.Users.create_magiclink_user(%{name: "magic user"})

      {:ok, _show_live, html} = live(conn, ~p"/users/#{user.raw_login_token}")

      assert html =~ "Show User"
      assert html =~ "magic user"
      assert get_session(conn, :user_id) == admin.id
    end

    test "a login token of a non-magic-link account does not open the record", %{conn: conn} do
      {_user, _token, login_token} = user_fixture_with_token()

      assert {:error, {:redirect, %{to: "/access/token"}}} =
               live(conn, ~p"/users/#{login_token}")
    end
  end
end
