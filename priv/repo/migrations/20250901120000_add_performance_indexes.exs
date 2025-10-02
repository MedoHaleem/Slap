defmodule Slap.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Direct messaging indexes
    execute("CREATE INDEX IF NOT EXISTS conversation_participants_user_id_index ON conversation_participants (user_id)")
    execute("CREATE INDEX IF NOT EXISTS conversation_participants_conversation_id_user_id_index ON conversation_participants (conversation_id, user_id)")
    execute("CREATE INDEX IF NOT EXISTS conversation_participants_conversation_id_role_index ON conversation_participants (conversation_id, role)")
    create index(:direct_messages, [:conversation_id, :inserted_at])
    create index(:direct_messages, [:user_id, :inserted_at])
    create index(:direct_messages, [:conversation_id, :user_id])
    create index(:conversation_invites, [:invitee_id, :status])
    execute("CREATE INDEX IF NOT EXISTS conversation_invites_token_index ON conversation_invites (token)")
    create index(:conversation_invites, [:expires_at])

    # Chat room indexes
    execute("CREATE INDEX IF NOT EXISTS room_memberships_user_id_index ON room_memberships (user_id)")
    create index(:room_memberships, [:room_id, :user_id], unique: true)
    create index(:room_memberships, [:room_id, :last_read_id])
    create index(:messages, [:room_id, :inserted_at])
    create index(:messages, [:user_id, :inserted_at])
    create index(:messages, [:room_id, :user_id])
    create index(:replies, [:message_id, :inserted_at])
    create index(:replies, [:user_id, :inserted_at])
    create index(:reactions, [:message_id, :emoji])
    create index(:reactions, [:user_id, :message_id])
    execute("CREATE INDEX IF NOT EXISTS message_attachments_message_id_index ON message_attachments (message_id)")

    # Full-text search indexes
    execute("CREATE INDEX IF NOT EXISTS messages_body_search ON messages USING gin(to_tsvector('english', body))")
    execute("CREATE INDEX IF NOT EXISTS direct_messages_body_search ON direct_messages USING gin(to_tsvector('english', body))")
    execute("CREATE INDEX IF NOT EXISTS replies_body_search ON replies USING gin(to_tsvector('english', body))")

    # Composite indexes for common queries
    create index(:conversations, [:type, :last_message_at])
    create index(:conversations, [:is_public, :type, :last_message_at])
    execute("CREATE INDEX IF NOT EXISTS rooms_name_index ON rooms (name)")
  end
end
