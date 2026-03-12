defmodule NullzaraWeb.SettingsController do
  use NullzaraWeb, :controller

  alias Nullzara.Users
  alias Nullzara.Users.Mnemonic

  def show(conn, _params) do
    user = conn.assigns.current_user
    changeset = Users.change_user(user)
    mnemonic_token = get_session(conn, :mnemonic_token)
    mnemonic = if mnemonic_token, do: Mnemonic.encode(mnemonic_token)
    render(conn, :show, user: user, changeset: changeset, mnemonic: mnemonic)
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Users.update_user(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Settings updated.")
        |> redirect(to: ~p"/user/#{user}/settings")

      {:error, changeset} ->
        mnemonic_token = get_session(conn, :mnemonic_token)
        mnemonic = if mnemonic_token, do: Mnemonic.encode(mnemonic_token)
        render(conn, :show, user: user, changeset: changeset, mnemonic: mnemonic)
    end
  end

  def regenerate_token(conn, _params) do
    user = conn.assigns.current_user

    case Users.regenerate_login_token(user) do
      {:ok, updated_user} ->
        conn
        |> put_flash(:new_login_token, updated_user.raw_login_token)
        |> redirect(to: ~p"/user/#{user}/settings")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not regenerate login token.")
        |> redirect(to: ~p"/user/#{user}/settings")
    end
  end

  def delete(conn, _params) do
    user = conn.assigns.current_user
    {:ok, _user} = Users.delete_user(user)

    conn
    |> clear_session()
    |> put_flash(:info, "Account deleted.")
    |> redirect(to: ~p"/")
  end
end
