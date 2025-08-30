defmodule Slap.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Slap.Chat` context.
  """

  alias Slap.Chat
  alias Slap.Chat.{Room, Message, MessageAttachment}
  alias Slap.Repo
  alias Slap.Accounts.User

  def room_fixture(attrs \\ %{}) do
    {:ok, room} =
      attrs
      |> Enum.into(%{
        name: "test-room-#{System.unique_integer([:positive])}",
        topic: "Test Room Topic"
      })
      |> Chat.create_room()

    room
  end

  def message_fixture(%Room{} = room, %User{} = user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "Test message #{System.unique_integer([:positive])}"})

    {:ok, message} = Chat.create_message(room, attrs, user)

    message
  end

  def attachment_fixture(%Message{} = message, attrs \\ %{}) do
    # Create a temporary PDF file for testing
    filename = "test-file-#{System.unique_integer([:positive])}.pdf"
    path = Path.join(["priv", "static", "uploads", filename])
    file_content = "%PDF-1.5\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, file_content)

    file_path = "/uploads/#{filename}"

    attachment = %MessageAttachment{
      message_id: message.id,
      file_path: file_path,
      file_name: attrs[:file_name] || "test.pdf",
      file_type: "application/pdf",
      file_size: attrs[:file_size] || 1024
    }

    {:ok, attachment} = Repo.insert(attachment)

    attachment
  end

  def reply_fixture(%Message{} = message, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "Test reply #{System.unique_integer([:positive])}"})

    {:ok, reply} = Chat.create_reply(message, attrs, message.user)

    reply
  end

  def join_room(%Room{} = room, %User{} = user) do
    Chat.join_room!(room, user)
  end
end
