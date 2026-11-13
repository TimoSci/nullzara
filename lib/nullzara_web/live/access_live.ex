defmodule NullzaraWeb.AccessLive do
  use NullzaraWeb, :live_view

  alias Nullzara.Users.Mnemonic

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Access Your Account
        <:subtitle>Enter your 12-word recovery phrase to access your account.</:subtitle>
      </.header>

      <.form for={@form} id="access-form" phx-change="validate" phx-submit="access">
        <.input
          field={@form[:phrase]}
          type="textarea"
          label="Recovery Phrase"
          placeholder="Enter your 12 words separated by spaces"
        />
        <p :if={@word_count > 0} class="text-sm mt-1 opacity-70">
          {word_count_text(@word_count)}
        </p>
        <footer class="flex items-center justify-between">
          <.button phx-disable-with="Verifying..." variant="primary">Access Account</.button>
          <.link navigate={~p"/access/token"} class="text-sm text-primary hover:underline">
            Login with token instead
          </.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"phrase" => ""}, as: :access)

    {:ok,
     socket
     |> assign(:page_title, "Access")
     |> assign(:form, form)
     |> assign(:word_count, 0)}
  end

  @impl true
  def handle_event("validate", %{"access" => %{"phrase" => phrase}}, socket) do
    word_count = phrase |> String.split() |> length()
    form = to_form(%{"phrase" => phrase}, as: :access)

    {:noreply,
     socket
     |> clear_flash(:error)
     |> assign(form: form, word_count: word_count)}
  end

  def handle_event("access", %{"access" => %{"phrase" => phrase}}, socket) do
    words = String.split(phrase)

    case Mnemonic.decode_words(words) do
      {:ok, token} ->
        # /u/:token is a controller route, so this is a full page redirect.
        # `via` sends a failed attempt back here instead of the token page.
        {:noreply, redirect(socket, to: ~p"/u/#{token}?via=mnemonic")}

      {:error, :invalid_length} ->
        {:noreply, put_flash(socket, :error, "Please enter exactly 12 words.")}

      {:error, :invalid_word} ->
        {:noreply, put_flash(socket, :error, "One or more words are not recognized.")}
    end
  end

  defp word_count_text(count) do
    "#{count} of 12 words entered"
  end
end
