defmodule Slap.Chat.DirectMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Accounts.User
  alias Slap.Chat.{Conversation, Reaction, MessageAttachment}

  @type t :: %__MODULE__{
          id: integer(),
          body: String.t(),
          conversation_id: integer(),
          user_id: integer(),
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          reactions: [Reaction.t()] | Ecto.Association.NotLoaded.t(),
          attachments: [MessageAttachment.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "direct_messages" do
    field :body, :string
    belongs_to :conversation, Conversation
    belongs_to :user, User
    has_many :reactions, Reaction
    has_many :attachments, MessageAttachment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(direct_message, attrs) do
    direct_message
    |> cast(attrs, [:body, :conversation_id, :user_id])
    |> validate_required([:body, :conversation_id, :user_id])
    |> validate_length(:body, max: 10_000)
    |> validate_format(:body, ~r/\S/, message: "cannot be whitespace only")
    |> assoc_constraint(:conversation)
    |> assoc_constraint(:user)
  end
end
