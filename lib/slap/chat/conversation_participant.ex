defmodule Slap.Chat.ConversationParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Accounts.User
  alias Slap.Chat.Conversation

  @roles ["admin", "moderator", "member", "restricted"]

  schema "conversation_participants" do
    belongs_to :conversation, Conversation
    belongs_to :user, User
    field :last_read_at, :utc_datetime
    field :role, :string, default: "member"
    field :joined_at, :utc_datetime
    field :notifications_enabled, :boolean, default: true
    field :can_invite, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation_participant, attrs) do
    conversation_participant
    |> cast(attrs, [:conversation_id, :user_id, :last_read_at, :role, :joined_at, :notifications_enabled, :can_invite])
    |> validate_required([:conversation_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> validate_number(:conversation_id, greater_than: 0)
    |> validate_number(:user_id, greater_than: 0)
    |> unique_constraint([:conversation_id, :user_id],
      name: :conversation_participants_conversation_id_user_id_index
    )
    |> maybe_set_joined_at()
  end

  defp maybe_set_joined_at(changeset) do
    case get_change(changeset, :joined_at) do
      nil -> put_change(changeset, :joined_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  def roles, do: @roles
end
