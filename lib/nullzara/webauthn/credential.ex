defmodule Nullzara.Webauthn.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "webauthn_credentials" do
    belongs_to :user, Nullzara.Users.User
    field :credential_id, :binary
    field :public_key, :map
    field :sign_count, :integer, default: 0
    field :friendly_name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:credential_id, :public_key, :sign_count, :friendly_name])
    |> validate_required([:credential_id, :public_key])
    |> unique_constraint(:credential_id)
    |> foreign_key_constraint(:user_id)
  end
end
