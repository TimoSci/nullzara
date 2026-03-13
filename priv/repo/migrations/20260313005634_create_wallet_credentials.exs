defmodule Nullzara.Repo.Migrations.CreateWalletCredentials do
  use Ecto.Migration

  def change do
    create table(:wallet_credentials) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :address, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:wallet_credentials, [:user_id])
    create unique_index(:wallet_credentials, [:address])
  end
end
