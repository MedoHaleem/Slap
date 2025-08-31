defmodule Slap.Chat.MessageAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Chat.Message
  alias Slap.Chat.DirectMessage

  schema "message_attachments" do
    field :file_name, :string
    field :file_path, :string
    field :file_size, :integer
    field :file_type, :string
    field :file, :any, virtual: true
    belongs_to :message, Message
    belongs_to :direct_message, DirectMessage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message_attachment, attrs) do
    message_attachment
    |> cast(attrs, [
      :file_path,
      :file_name,
      :file_type,
      :file_size,
      :message_id,
      :direct_message_id
    ])
    |> validate_required([:file_path, :file_name, :file_type, :file_size])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:direct_message_id)
    |> validate_pdf_file_type()
    |> validate_exclusive_association()
  end

  def upload_changeset(message_attachment, attrs) do
    message_attachment
    |> cast(attrs, [:file, :message_id, :direct_message_id])
    |> validate_required([:file])
    |> validate_file()
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:direct_message_id)
    |> validate_exclusive_association()
  end

  defp validate_file(changeset) do
    case get_change(changeset, :file) do
      %Plug.Upload{} = upload ->
        if String.downcase(Path.extname(upload.filename)) == ".pdf" do
          file_size =
            if File.exists?(upload.path) do
              File.stat!(upload.path).size
            else
              0
            end

          changeset
          |> put_change(:file_name, upload.filename)
          |> put_change(:file_type, upload.content_type)
          |> put_change(:file_size, file_size)
        else
          add_error(changeset, :file, "Only PDF files are allowed")
        end

      _ ->
        add_error(changeset, :file, "Invalid file")
    end
  end

  defp validate_pdf_file_type(changeset) do
    case get_field(changeset, :file_type) do
      "application/pdf" -> changeset
      _ -> add_error(changeset, :file_type, "Only PDF files are allowed")
    end
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
