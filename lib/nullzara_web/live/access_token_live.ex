defmodule NullzaraWeb.AccessTokenLive do
  use NullzaraWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Access Your Account
        <:subtitle>Enter your access token to log in.</:subtitle>
      </.header>

      <.form for={@form} id="token-form" phx-submit="access">
        <.input
          field={@form[:token]}
          type="text"
          label="Access Token"
          placeholder="Enter your 32-character hex token"
        />
        <footer class="flex items-center justify-between">
          <.button phx-disable-with="Verifying..." variant="primary">Access Account</.button>
          <.link navigate={~p"/access/mnemonic"} class="text-sm text-primary hover:underline">
            Login with recovery phrase instead
          </.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"token" => ""}, as: :access)

    {:ok,
     socket
     |> assign(:page_title, "Access")
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("access", %{"access" => %{"token" => token}}, socket) do
    token = String.trim(token)

    if String.match?(token, ~r/\A[0-9a-fA-F]{32}\z/) do
      {:noreply, push_navigate(socket, to: ~p"/u/#{token}")}
    else
      {:noreply,
       put_flash(socket, :error, "Invalid token format. Please enter a 32-character hex token.")}
    end
  end
end
