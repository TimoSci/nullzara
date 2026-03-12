defmodule Nullzara.Repo do
  use Ecto.Repo,
    otp_app: :nullzara,
    adapter: Ecto.Adapters.Postgres
end
