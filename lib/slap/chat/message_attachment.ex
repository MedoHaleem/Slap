defmodule Slap.Chat.MessageAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Slap.Chat.Message

  schema "message_attachments" do
    field :file_name, :string
    field :file_path, :string
    field :file_size, :integer
    field :file_type, :string
    field :file, :any, virtual: true
    belongs_to :message, Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message_attachment, attrs) do
    message_attachment
    |> cast(attrs, [:file_path, :file_name, :file_type, :file_size, :message_id])
    |> validate_required([:file_path, :file_name, :file_type, :file_size, :message_id])
    |> foreign_key_constraint(:message_id)
    |> validate_pdf_file_type()
  end

  def upload_changeset(message_attachment, attrs) do
    message_attachment
    |> cast(attrs, [:file, :message_id])
    |> validate_required([:file, :message_id])
    |> validate_file()
    |> foreign_key_constraint(:message_id)
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
end
