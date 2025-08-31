defmodule Slap.Chat.ConversationParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Accounts.User
  alias Slap.Chat.Conversation

  schema "conversation_participants" do
    belongs_to :conversation, Conversation
    belongs_to :user, User
    field :last_read_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation_participant, attrs) do
    conversation_participant
    |> cast(attrs, [:conversation_id, :user_id, :last_read_at])
    |> validate_required([:conversation_id, :user_id])
    |> validate_number(:conversation_id, greater_than: 0)
    |> validate_number(:user_id, greater_than: 0)
    |> unique_constraint([:conversation_id, :user_id],
      name: :conversation_participants_conversation_id_user_id_index
    )
  end
end
