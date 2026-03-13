defmodule Nullzara.Wallet.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallet_credentials" do
    belongs_to :user, Nullzara.Users.User
    field :address, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:address])
    |> validate_required([:address])
    |> update_change(:address, &String.downcase/1)
    |> unique_constraint(:address)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
