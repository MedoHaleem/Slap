defmodule Slap.Repo.Migrations.AddDirectMessagingPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite index for cursor-based pagination on messages
    # This optimizes the ORDER BY inserted_at DESC, id DESC queries
    create index(:direct_messages, [:conversation_id, :inserted_at, :id],
             name: :direct_messages_conversation_cursor_idx
           )

    # Index for unread count calculations
    create index(:conversation_participants, [:user_id, :last_read_at],
             name: :conversation_participants_unread_calc_idx
           )

    # Composite index for conversation read status queries
    create index(:conversation_participants, [:conversation_id, :last_read_at],
             name: :conversation_participants_read_status_idx
           )

    # Index for efficient conversation lookup between users
    create index(:conversation_participants, [:user_id, :conversation_id],
             name: :conversation_participants_conversation_lookup_idx
           )

    # Index for message search by conversation and timestamp
    create index(:direct_messages, [:conversation_id, :inserted_at],
             name: :direct_messages_conversation_time_idx
           )
  end
end
