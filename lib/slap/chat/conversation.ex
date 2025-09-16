defmodule Slap.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Chat.{DirectMessage, ConversationParticipant, ConversationSetting, ConversationInvite}

  @conversation_types ["direct", "group", "channel"]
  @max_participants 1000

  schema "conversations" do
    field :title, :string
    field :description, :string
    field :last_message_at, :utc_datetime
    field :participant_count, :integer, default: 0
    field :type, :string, default: "direct"
    field :is_public, :boolean, default: false
    field :avatar_path, :string
    field :settings, :map, default: %{}

    has_many :conversation_participants, ConversationParticipant
    has_many :direct_messages, DirectMessage
    has_one :conversation_setting, ConversationSetting
    has_many :conversation_invites, ConversationInvite

    # Virtual fields for UI
    field :current_user_role, :string, virtual: true
    field :unread_count, :integer, virtual: true, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :description, :last_message_at, :type, :is_public, :avatar_path, :settings])
    |> validate_required([:title, :type])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:type, @conversation_types)
    |> validate_format(:title, ~r/\S/, message: "cannot be whitespace only")
    |> maybe_generate_default_title()
  end

  defp maybe_generate_default_title(changeset) do
    case get_change(changeset, :title) do
      nil ->
        case get_field(changeset, :type) do
          "direct" -> changeset
          _ -> put_change(changeset, :title, "New Group Conversation")
        end
      _ -> changeset
    end
  end

  def conversation_types, do: @conversation_types
  def max_participants, do: @max_participants
end
