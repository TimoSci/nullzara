defmodule NullzaraWeb.DashboardController do
  use NullzaraWeb, :controller

  def show(conn, _params) do
    render(conn, :show, user: conn.assigns.current_user)
  end
end
