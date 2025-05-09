defmodule Slap.Chat.RoomMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Accounts.User
  alias Slap.Chat.Room

  schema "room_memberships" do
    belongs_to :room, Room
    belongs_to :user, User

    field :last_read_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(room_membership, attrs) do
    room_membership
    |> cast(attrs, [])
    |> validate_required([])
  end
end
