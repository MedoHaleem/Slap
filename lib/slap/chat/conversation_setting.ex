defmodule Slap.Chat.ConversationSetting do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Chat.Conversation

  @max_participants 1000
  @min_participants 2

  @type t :: %__MODULE__{
          id: integer(),
          conversation_id: integer(),
          allow_participant_invites: boolean(),
          require_admin_approval: boolean(),
          message_editing_enabled: boolean(),
          file_sharing_enabled: boolean(),
          max_participants: integer(),
          custom_fields: map(),
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "conversation_settings" do
    belongs_to :conversation, Conversation
    field :allow_participant_invites, :boolean, default: true
    field :require_admin_approval, :boolean, default: false
    field :message_editing_enabled, :boolean, default: true
    field :file_sharing_enabled, :boolean, default: true
    field :max_participants, :integer, default: 100
    field :custom_fields, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation_setting, attrs) do
    conversation_setting
    |> cast(attrs, [
      :conversation_id,
      :allow_participant_invites,
      :require_admin_approval,
      :message_editing_enabled,
      :file_sharing_enabled,
      :max_participants,
      :custom_fields
    ])
    |> validate_required([:conversation_id])
    |> validate_number(:conversation_id, greater_than: 0)
    |> validate_number(:max_participants,
      greater_than_or_equal_to: @min_participants,
      less_than_or_equal_to: @max_participants
    )
    |> assoc_constraint(:conversation)
    |> unique_constraint(:conversation_id)
  end

  def max_participants, do: @max_participants
  def min_participants, do: @min_participants
end
