defmodule NullzaraWeb.UserLive.Show do
  use NullzaraWeb, :live_view

  alias Nullzara.Users

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
  def mount(%{"id" => id}, _session, socket) do
    user = lookup_user(id)

    {:ok,
     socket
     |> assign(:page_title, "Show User")
     |> assign(:user, user)}
  end

  defp lookup_user(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Users.get_user_by_uuid!(uuid)

      :error ->
        case Users.get_user_by_login_token(id) do
          {:ok, user} -> user
          {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Nullzara.Users.User
        end
    end
  end
end
