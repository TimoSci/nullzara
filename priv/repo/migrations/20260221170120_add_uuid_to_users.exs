defmodule Userphoenix.Repo.Migrations.AddUuidToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :uuid, :uuid, default: fragment("gen_random_uuid()"), null: false
    end

    create unique_index(:users, [:uuid])
  end
end
