defmodule Slap.Chat.ConversationInvite do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Accounts.User
  alias Slap.Chat.Conversation

  @statuses ["pending", "accepted", "declined", "expired"]
  @invite_expiry_days 7

  schema "conversation_invites" do
    belongs_to :conversation, Conversation
    belongs_to :inviter, User
    belongs_to :invitee, User
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    field :token, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation_invite, attrs) do
    conversation_invite
    |> cast(attrs, [:conversation_id, :inviter_id, :invitee_id, :status, :expires_at, :token])
    |> validate_required([:conversation_id, :inviter_id, :invitee_id, :status, :token])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:conversation_id, greater_than: 0)
    |> validate_number(:inviter_id, greater_than: 0)
    |> validate_number(:invitee_id, greater_than: 0)
    |> assoc_constraint(:conversation)
    |> assoc_constraint(:inviter)
    |> assoc_constraint(:invitee)
    |> unique_constraint([:conversation_id, :invitee_id])
    |> validate_inviter_not_invitee()
    |> maybe_set_expires_at()
    |> maybe_generate_token()
  end

  defp validate_inviter_not_invitee(changeset) do
    inviter_id = get_change(changeset, :inviter_id)
    invitee_id = get_change(changeset, :invitee_id)

    if inviter_id && invitee_id && inviter_id == invitee_id do
      add_error(changeset, :invitee_id, "cannot invite yourself")
    else
      changeset
    end
  end

  defp maybe_set_expires_at(changeset) do
    case get_change(changeset, :expires_at) do
      nil ->
        expires_at = DateTime.utc_now()
        |> DateTime.add(@invite_expiry_days * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)
        put_change(changeset, :expires_at, expires_at)
      _ -> changeset
    end
  end

  defp maybe_generate_token(changeset) do
    case get_change(changeset, :token) do
      nil -> put_change(changeset, :token, generate_unique_token())
      _ -> changeset
    end
  end

  defp generate_unique_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 32)
  end

  def statuses, do: @statuses
  def invite_expiry_days, do: @invite_expiry_days
end
