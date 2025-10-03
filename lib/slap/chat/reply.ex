defmodule Slap.Chat.Reply do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Chat.Message
  alias Slap.Accounts.User

  @type t :: %__MODULE__{
          id: integer(),
          body: String.t(),
          message_id: integer(),
          user_id: integer(),
          message: Message.t() | Ecto.Association.NotLoaded.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "replies" do
    field :body, :string
    belongs_to :message, Message
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:body])
    |> validate_required([:body])
  end
end
