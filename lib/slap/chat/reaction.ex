defmodule Slap.Chat.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Accounts.User
  alias Slap.Chat.Message
  alias Slap.Chat.DirectMessage

  schema "reactions" do
    field :emoji, :string
    belongs_to :user, User
    belongs_to :message, Message
    belongs_to :direct_message, DirectMessage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :direct_message_id])
    |> unique_constraint([:emoji, :message_id, :user_id])
    |> validate_required([:emoji])
    |> validate_exclusive_association()
  end

  defp validate_exclusive_association(changeset) do
    message_id = get_change(changeset, :message_id)
    direct_message_id = get_change(changeset, :direct_message_id)

    cond do
      not is_nil(message_id) and not is_nil(direct_message_id) ->
        add_error(changeset, :base, "Cannot belong to both message and direct message")

      is_nil(message_id) and is_nil(direct_message_id) ->
        add_error(changeset, :base, "Must belong to either message or direct message")

      true ->
        changeset
    end
  end
end
