defmodule Slap.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Chat.{DirectMessage, ConversationParticipant}

  schema "conversations" do
    field :title, :string
    field :last_message_at, :utc_datetime
    field :participant_count, :integer, default: 0

    has_many :conversation_participants, ConversationParticipant
    has_many :direct_messages, DirectMessage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :last_message_at])
    |> validate_required([:title])
    |> validate_length(:title, max: 255)
    |> validate_format(:title, ~r/\S/, message: "cannot be whitespace only")
  end
end
