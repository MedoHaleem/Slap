defmodule Slap.Repo.Migrations.AddGroupConversationPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite indexes for group queries
    create index(:conversation_participants, [:conversation_id, :user_id, :role],
             name: :idx_participants_conversation_role
           )

    create index(:conversation_participants, [:user_id, :conversation_id, :role],
             name: :idx_participants_user_role
           )

    # Partial indexes for active groups
    execute """
    CREATE INDEX idx_groups_active ON conversations (last_message_at, participant_count)
    WHERE type = 'group' AND last_message_at IS NOT NULL
    """

    # Index for public group discovery
    create index(:conversations, [:is_public, :last_message_at],
             where: "is_public = true",
             name: :idx_public_groups
           )

    # Index for participant count queries
    create index(:conversations, [:participant_count],
             where: "participant_count > 2",
             name: :idx_large_groups
           )

    # Index for conversation invites status queries
    create index(:conversation_invites, [:invitee_id, :status],
             name: :idx_invites_user_status
           )

    create index(:conversation_invites, [:conversation_id, :status],
             name: :idx_invites_conversation_status
           )

    # Partial index for pending invites
    create index(:conversation_invites, [:expires_at],
             where: "status = 'pending'",
             name: :idx_pending_invites_expiry
           )
  end
end
