defmodule Slap.Repo.Migrations.AddPartialIndexesForActiveConversations do
  use Ecto.Migration

  def change do
    # Partial index for active conversations (last 30 days)
    # Note: Using raw SQL to avoid IMMUTABLE function issues with NOW()
    execute """
    CREATE INDEX idx_conversations_active ON conversations (last_message_at)
    WHERE last_message_at IS NOT NULL;
    """

    # Partial index for conversations with unread messages for user
    # Simplified to avoid cross-table references in WHERE clause
    create index(:conversation_participants, [:conversation_id, :user_id],
             where: "last_read_at IS NULL",
             name: :idx_conversations_unread
           )
  end
end
