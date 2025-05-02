defmodule Slap.Repo.Migrations.CreateMessageAttachments do
  use Ecto.Migration

  def change do
    create table(:message_attachments) do
      add :file_path, :string
      add :file_name, :string
      add :file_type, :string
      add :file_size, :integer
      add :message_id, references(:messages, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:message_attachments, [:message_id])
  end
end
