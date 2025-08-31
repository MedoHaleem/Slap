defmodule Slap.Chat.ConversationTest do
  use Slap.DataCase, async: true

  alias Slap.Chat.Conversation

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{title: "Test Conversation"}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      assert changeset.valid?
      assert changeset.changes.title == "Test Conversation"
    end

    test "invalid changeset missing title" do
      attrs = %{}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts empty title" do
      attrs = %{title: ""}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts very long titles" do
      long_title = String.duplicate("a", 255)
      attrs = %{title: long_title}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      assert changeset.valid?
    end

    test "rejects titles that are too long" do
      too_long_title = String.duplicate("a", 256)
      attrs = %{title: too_long_title}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      refute changeset.valid?
      assert %{title: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end
  end

  describe "associations" do
    test "has many direct_messages" do
      direct_messages_assoc = Conversation.__schema__(:association, :direct_messages)
      assert direct_messages_assoc != nil
      assert direct_messages_assoc.related == Slap.Chat.DirectMessage
      assert direct_messages_assoc.owner_key == :id
    end

    test "has many conversation_participants" do
      participants_assoc = Conversation.__schema__(:association, :conversation_participants)
      assert participants_assoc != nil
      assert participants_assoc.related == Slap.Chat.ConversationParticipant
      assert participants_assoc.owner_key == :id
    end
  end

  describe "schema fields" do
    test "has title field" do
      assert Conversation.__schema__(:type, :title) == :string
    end

    test "has last_message_at field" do
      assert Conversation.__schema__(:type, :last_message_at) == :utc_datetime
    end

    test "has timestamps" do
      assert Conversation.__schema__(:type, :inserted_at) == :utc_datetime
      assert Conversation.__schema__(:type, :updated_at) == :utc_datetime
    end

    test "has correct table name" do
      assert Conversation.__schema__(:source) == "conversations"
    end
  end

  describe "edge cases" do
    test "handles nil values gracefully" do
      attrs = %{title: nil}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "handles special characters in title" do
      special_titles = [
        "Test & Conversation",
        "Test @ Conversation",
        "Test # Conversation",
        "Test $ Conversation"
      ]

      for title <- special_titles do
        attrs = %{title: title}
        changeset = Conversation.changeset(%Conversation{}, attrs)
        assert changeset.valid?, "Title '#{title}' should be valid"
      end
    end

    test "handles unicode characters in title" do
      unicode_titles = ["Test 😊 Conversation", "Test ñ Conversation", "Test 中文 Conversation"]

      for title <- unicode_titles do
        attrs = %{title: title}
        changeset = Conversation.changeset(%Conversation{}, attrs)
        assert changeset.valid?, "Unicode title '#{title}' should be valid"
      end
    end

    test "handles whitespace-only title" do
      attrs = %{title: "   "}
      changeset = Conversation.changeset(%Conversation{}, attrs)

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
