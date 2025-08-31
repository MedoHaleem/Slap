defmodule Slap.Repo.Migrations.CreateDirectMessagingTables do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :title, :string
      add :last_message_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:conversation_participants) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:direct_messages) do
      add :body, :text, null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversation_participants, [:conversation_id])
    create index(:conversation_participants, [:user_id])
    create unique_index(:conversation_participants, [:conversation_id, :user_id])

    create index(:direct_messages, [:conversation_id])
    create index(:direct_messages, [:user_id])
    create index(:direct_messages, [:inserted_at])

    # For performance when fetching conversations with latest messages
    create index(:conversations, [:last_message_at])

    # For full-text search in direct messages
    execute """
    CREATE INDEX direct_messages_body_search_idx ON direct_messages
    USING GIN (to_tsvector('english', body))
    """
  end
end
