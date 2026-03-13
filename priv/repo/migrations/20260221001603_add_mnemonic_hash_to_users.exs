defmodule Nullzara.Repo.Migrations.AddMnemonicHashToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :mnemonic_hash, :string
    end

    flush()

    execute "UPDATE users SET mnemonic_hash = token_hash", ""

    create unique_index(:users, [:mnemonic_hash])
  end
end
