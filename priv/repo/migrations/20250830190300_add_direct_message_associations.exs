defmodule Slap.Repo.Migrations.AddDirectMessageAssociations do
  use Ecto.Migration

  def change do
    alter table(:reactions) do
      add :direct_message_id, references(:direct_messages, on_delete: :delete_all)
    end

    alter table(:message_attachments) do
      add :direct_message_id, references(:direct_messages, on_delete: :delete_all)
    end

    create index(:reactions, [:direct_message_id])
    create index(:message_attachments, [:direct_message_id])
  end
end
