defmodule Slap.Repo.Migrations.AddAdditionalCompositeIndexes do
  use Ecto.Migration

  def change do
    # For efficient participant status queries
    create index(:conversation_participants, [:conversation_id, :user_id, :last_read_at],
             name: :idx_conversation_participants_status
           )

    # For conversation membership queries
    create index(:conversation_participants, [:user_id, :conversation_id, :inserted_at],
             name: :idx_conversation_participants_membership
           )
  end
end
