defmodule Slap.DirectMessagingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Slap.DirectMessaging` context.
  """

  alias Slap.DirectMessaging
  alias Slap.Accounts.User
  alias Slap.Repo
  alias Slap.Chat.{DirectMessage, Conversation, ConversationParticipant}

  def unique_conversation_title, do: "Conversation #{System.unique_integer([:positive])}"

  def valid_conversation_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: unique_conversation_title()
    })
  end

  def conversation_fixture(attrs \\ %{}) do
    {:ok, conversation} =
      attrs
      |> valid_conversation_attributes()
      |> DirectMessaging.create_conversation()

    conversation
  end

  def conversation_with_participants_fixture(%User{} = user1, %User{} = user2, attrs \\ %{}) do
    {:ok, conversation} =
      attrs
      |> valid_conversation_attributes()
      |> DirectMessaging.create_conversation_with_participants([user1.id, user2.id])

    conversation
  end

  def valid_direct_message_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      body: "Test message #{System.unique_integer([:positive])}"
    })
  end

  def direct_message_fixture(%Conversation{} = conversation, %User{} = user, attrs \\ %{}) do
    attrs = valid_direct_message_attributes(attrs)

    # Ensure the user is a participant in the conversation
    case DirectMessaging.get_conversation_participant(conversation.id, user.id) do
      nil ->
        # Add the user as a participant if they're not already
        {:ok, _} = DirectMessaging.add_participant_to_conversation(conversation, user.id)

      _participant ->
        # User is already a participant
        :ok
    end

    {:ok, direct_message} = DirectMessaging.send_direct_message(conversation, attrs, user)

    # Preload the same associations as get_direct_message!/1
    direct_message |> Repo.preload([:user, :attachments, :reactions])
  end

  def conversation_participant_fixture(
        %Conversation{} = conversation,
        %User{} = user,
        attrs \\ %{}
      ) do
    participant_attrs =
      Enum.into(attrs, %{
        last_read_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %ConversationParticipant{}
    |> ConversationParticipant.changeset(
      Map.put(participant_attrs, :conversation_id, conversation.id)
    )
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert!()
  end

  def direct_message_attachment_fixture(%DirectMessage{} = direct_message, attrs \\ %{}) do
    # Create a temporary PDF file for testing
    filename = "test-dm-file-#{System.unique_integer([:positive])}.pdf"
    path = Path.join(["priv", "static", "uploads", filename])
    file_content = "%PDF-1.5\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, file_content)

    file_path = "/uploads/#{filename}"

    attachment = %Slap.Chat.MessageAttachment{
      direct_message_id: direct_message.id,
      file_path: file_path,
      file_name: attrs[:file_name] || "test.pdf",
      file_type: "application/pdf",
      file_size: attrs[:file_size] || 1024
    }

    {:ok, attachment} = Repo.insert(attachment)

    attachment
  end

  def direct_message_reaction_fixture(
        %DirectMessage{} = direct_message,
        %User{} = user,
        attrs \\ %{}
      ) do
    reaction_attrs =
      Enum.into(attrs, %{
        emoji: "👍"
      })

    %Slap.Chat.Reaction{}
    |> Slap.Chat.Reaction.changeset(
      Map.merge(reaction_attrs, %{
        direct_message_id: direct_message.id,
        user_id: user.id
      })
    )
    |> Repo.insert!()
  end
end
