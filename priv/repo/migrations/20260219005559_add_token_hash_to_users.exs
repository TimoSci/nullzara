defmodule Nullzara.Repo.Migrations.AddTokenHashToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :token_hash, :string
    end

    create unique_index(:users, [:token_hash])
  end
end
