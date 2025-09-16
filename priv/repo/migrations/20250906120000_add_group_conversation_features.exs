defmodule Slap.Repo.Migrations.AddGroupConversationFeatures do
  use Ecto.Migration

  def change do
    # Add conversation type and settings
    alter table(:conversations) do
      add :type, :string, default: "direct", null: false
      add :description, :text
      add :is_public, :boolean, default: false, null: false
      add :avatar_path, :string
      add :settings, :map, default: %{}
    end

    # Add participant roles
    alter table(:conversation_participants) do
      add :role, :string, default: "member", null: false
      add :joined_at, :utc_datetime
      add :notifications_enabled, :boolean, default: true, null: false
      add :can_invite, :boolean, default: false, null: false
    end

    # Create conversation settings table
    create table(:conversation_settings) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :allow_participant_invites, :boolean, default: true, null: false
      add :require_admin_approval, :boolean, default: false, null: false
      add :message_editing_enabled, :boolean, default: true, null: false
      add :file_sharing_enabled, :boolean, default: true, null: false
      add :max_participants, :integer, default: 100, null: false
      add :custom_fields, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Create conversation invites table
    create table(:conversation_invites) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, on_delete: :delete_all), null: false
      add :invitee_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, default: "pending", null: false
      add :expires_at, :utc_datetime
      add :token, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Create indexes
    create index(:conversations, [:type])
    create index(:conversations, [:is_public])
    create index(:conversation_participants, [:role])
    create index(:conversation_participants, [:conversation_id, :role])
    create index(:conversation_settings, [:conversation_id])
    create index(:conversation_invites, [:conversation_id])
    create index(:conversation_invites, [:invitee_id])
    create index(:conversation_invites, [:token])
    create unique_index(:conversation_invites, [:conversation_id, :invitee_id])

    # Add check constraints
    execute """
    ALTER TABLE conversations
    ADD CONSTRAINT conversations_type_check
    CHECK (type IN ('direct', 'group', 'channel'))
    """

    execute """
    ALTER TABLE conversation_participants
    ADD CONSTRAINT participants_role_check
    CHECK (role IN ('admin', 'moderator', 'member', 'restricted'))
    """

    execute """
    ALTER TABLE conversation_invites
    ADD CONSTRAINT invites_status_check
    CHECK (status IN ('pending', 'accepted', 'declined', 'expired'))
    """

    # Update existing conversations to be 'direct' type
    execute "UPDATE conversations SET type = 'direct' WHERE type IS NULL"

    # Update existing participants to be 'member' role with invite permissions for 2-person conversations
    execute """
    UPDATE conversation_participants
    SET role = 'member',
        can_invite = true,
        joined_at = inserted_at
    WHERE role IS NULL
    """

    # Create settings for existing conversations
    execute """
    INSERT INTO conversation_settings (conversation_id, allow_participant_invites, require_admin_approval,
                                     message_editing_enabled, file_sharing_enabled, max_participants,
                                     inserted_at, updated_at)
    SELECT id, true, false, true, true, 100, NOW(), NOW()
    FROM conversations
    WHERE type = 'direct'
    """
  end
end
