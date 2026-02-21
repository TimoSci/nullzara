defmodule UserphoenixWeb.UserLive.Show do
  use UserphoenixWeb, :live_view

  alias Userphoenix.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        User {@user.id}
        <:subtitle>This is a user record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/users"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/users/#{@user}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit user
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@user.name}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"uuid" => uuid}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show User")
     |> assign(:user, Users.get_user_by_uuid!(uuid))}
  end
end
