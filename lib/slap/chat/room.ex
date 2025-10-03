defmodule Slap.Chat.Room do
  use Ecto.Schema
  import Ecto.Changeset
  alias Slap.Accounts.User
  alias Slap.Chat.{Message, RoomMembership}

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          topic: String.t() | nil,
          members: [User.t()] | Ecto.Association.NotLoaded.t(),
          memberships: [RoomMembership.t()] | Ecto.Association.NotLoaded.t(),
          messages: [Message.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "rooms" do
    field :name, :string
    field :topic, :string

    many_to_many :members, User, join_through: RoomMembership
    has_many :memberships, RoomMembership
    has_many :messages, Slap.Chat.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :topic])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_format(:name, ~r/\A[a-z0-9-]+\z/,
      message: "can only contain lowercase letters, numbers and dashes"
    )
    |> validate_length(:topic, max: 200)
    |> unique_constraint(:name)
  end
end
