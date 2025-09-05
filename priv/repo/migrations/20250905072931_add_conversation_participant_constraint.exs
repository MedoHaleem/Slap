defmodule Slap.Repo.Migrations.AddConversationParticipantConstraint do
  use Ecto.Migration

  def change do
    # Add participant_count column to conversations table
    alter table(:conversations) do
      add :participant_count, :integer, default: 0, null: false
    end

    # Create function to update participant count
    execute """
    CREATE OR REPLACE FUNCTION update_conversation_participant_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        UPDATE conversations SET participant_count = participant_count + 1
        WHERE id = NEW.conversation_id;
        RETURN NEW;
      ELSIF TG_OP = 'DELETE' THEN
        UPDATE conversations SET participant_count = participant_count - 1
        WHERE id = OLD.conversation_id;
        RETURN OLD;
      END IF;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to maintain participant count
    execute """
    CREATE TRIGGER conversation_participant_count_trigger
      AFTER INSERT OR DELETE ON conversation_participants
      FOR EACH ROW EXECUTE FUNCTION update_conversation_participant_count();
    """

    # Populate participant_count for existing conversations
    execute """
    UPDATE conversations
    SET participant_count = (
      SELECT COUNT(*)
      FROM conversation_participants cp
      WHERE cp.conversation_id = conversations.id
    );
    """

    # Add check constraint for minimum 2 participants (initially deferrable)
    execute """
    ALTER TABLE conversations
    ADD CONSTRAINT conversations_minimum_participants
    CHECK (participant_count >= 2) NOT VALID;
    """

    # Validate the constraint after data is populated
    execute """
    ALTER TABLE conversations
    VALIDATE CONSTRAINT conversations_minimum_participants;
    """
  end
end
