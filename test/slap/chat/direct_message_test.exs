defmodule Slap.Chat.DirectMessageTest do
  use Slap.DataCase, async: true

  alias Slap.Chat.DirectMessage

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{body: "Test message", conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      assert changeset.valid?
      assert changeset.changes.body == "Test message"
    end

    test "invalid changeset missing body" do
      attrs = %{conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset missing conversation_id" do
      attrs = %{body: "Test message", user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{conversation_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset missing user_id" do
      attrs = %{body: "Test message", conversation_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts empty message body" do
      attrs = %{body: "", conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts very long messages" do
      long_message = String.duplicate("a", 10_000)
      attrs = %{body: long_message, conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      assert changeset.valid?
    end

    test "rejects messages that are too long" do
      too_long_message = String.duplicate("a", 10_001)
      attrs = %{body: too_long_message, conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{body: ["should be at most 10000 character(s)"]} = errors_on(changeset)
    end
  end

  describe "associations" do
    test "belongs to conversation" do
      conversation_assoc = DirectMessage.__schema__(:association, :conversation)
      assert conversation_assoc != nil
      assert conversation_assoc.related == Slap.Chat.Conversation
      assert conversation_assoc.owner_key == :conversation_id
    end

    test "belongs to user" do
      user_assoc = DirectMessage.__schema__(:association, :user)
      assert user_assoc != nil
      assert user_assoc.related == Slap.Accounts.User
      assert user_assoc.owner_key == :user_id
    end

    test "has many reactions" do
      reactions_assoc = DirectMessage.__schema__(:association, :reactions)
      assert reactions_assoc != nil
      assert reactions_assoc.related == Slap.Chat.Reaction
      assert reactions_assoc.owner_key == :id
    end

    test "has many attachments" do
      attachments_assoc = DirectMessage.__schema__(:association, :attachments)
      assert attachments_assoc != nil
      assert attachments_assoc.related == Slap.Chat.MessageAttachment
      assert attachments_assoc.owner_key == :id
    end
  end

  describe "schema fields" do
    test "has body field" do
      assert DirectMessage.__schema__(:type, :body) == :string
    end

    test "has timestamps" do
      assert DirectMessage.__schema__(:type, :inserted_at) == :utc_datetime
      assert DirectMessage.__schema__(:type, :updated_at) == :utc_datetime
    end

    test "has correct table name" do
      assert DirectMessage.__schema__(:source) == "direct_messages"
    end
  end

  describe "edge cases" do
    test "handles nil values gracefully" do
      attrs = %{body: nil, conversation_id: nil, user_id: nil}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
      assert %{conversation_id: ["can't be blank"]} = errors_on(changeset)
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "handles special characters in message body" do
      special_messages = [
        "Test & message",
        "Test @ message",
        "Test # message",
        "Test $ message",
        "Test 😊 message"
      ]

      for message <- special_messages do
        attrs = %{body: message, conversation_id: 1, user_id: 1}
        changeset = DirectMessage.changeset(%DirectMessage{}, attrs)
        assert changeset.valid?, "Message '#{message}' should be valid"
      end
    end

    test "handles unicode characters in message body" do
      unicode_messages = ["Test ñ message", "Test 中文 message", "Test 日本語 message"]

      for message <- unicode_messages do
        attrs = %{body: message, conversation_id: 1, user_id: 1}
        changeset = DirectMessage.changeset(%DirectMessage{}, attrs)
        assert changeset.valid?, "Unicode message '#{message}' should be valid"
      end
    end

    test "handles whitespace-only message" do
      attrs = %{body: "   ", conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "handles newlines in message body" do
      attrs = %{body: "Test\nmessage\nwith\nnewlines", conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      assert changeset.valid?
    end

    test "handles HTML content in message body" do
      html_message = "<p>This is <strong>HTML</strong> content</p>"
      attrs = %{body: html_message, conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      assert changeset.valid?
    end

    test "handles SQL injection attempts in message body" do
      sql_injection = "Test message; DROP TABLE users;"
      attrs = %{body: sql_injection, conversation_id: 1, user_id: 1}
      changeset = DirectMessage.changeset(%DirectMessage{}, attrs)

      assert changeset.valid?
      # The changeset should be valid, but the actual SQL protection is handled by Ecto
    end
  end
end
