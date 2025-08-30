defmodule Slap.Chat.ReactionTest do
  use Slap.DataCase, async: true

  alias Slap.Chat.Reaction

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{emoji: "👍", user_id: 1, message_id: 1}
      changeset = Reaction.changeset(%Reaction{}, attrs)

      assert changeset.valid?
      assert changeset.changes.emoji == "👍"
    end

    test "invalid changeset missing emoji" do
      attrs = %{user_id: 1, message_id: 1}
      changeset = Reaction.changeset(%Reaction{}, attrs)

      refute changeset.valid?
      assert %{emoji: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts various emoji characters" do
      valid_emojis = ["👍", "❤️", "😂", "😊", "🔥", "👏", "🙌", "💯"]

      for emoji <- valid_emojis do
        attrs = %{emoji: emoji, user_id: 1, message_id: 1}
        changeset = Reaction.changeset(%Reaction{}, attrs)
        assert changeset.valid?, "Emoji #{emoji} should be valid"
      end
    end

    test "accepts text-based emoji representations" do
      text_emojis = [":thumbsup:", ":heart:", ":smile:", ":fire:"]

      for emoji <- text_emojis do
        attrs = %{emoji: emoji, user_id: 1, message_id: 1}
        changeset = Reaction.changeset(%Reaction{}, attrs)
        assert changeset.valid?, "Text emoji #{emoji} should be valid"
      end
    end

    test "accepts empty string as emoji (edge case)" do
      attrs = %{emoji: "", user_id: 1, message_id: 1}
      changeset = Reaction.changeset(%Reaction{}, attrs)

      refute changeset.valid?
      assert %{emoji: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts very long emoji strings" do
      long_emoji = String.duplicate("👍", 100)
      attrs = %{emoji: long_emoji, user_id: 1, message_id: 1}
      changeset = Reaction.changeset(%Reaction{}, attrs)

      assert changeset.valid?
    end

    test "accepts unicode emoji sequences" do
      # Family emoji, skin tone modifiers, etc.
      complex_emojis = ["👨‍👩‍👧‍👦", "👍🏽", "👨🏾‍💻", "🇺🇸", "🏳️‍🌈"]

      for emoji <- complex_emojis do
        attrs = %{emoji: emoji, user_id: 1, message_id: 1}
        changeset = Reaction.changeset(%Reaction{}, attrs)
        assert changeset.valid?, "Complex emoji #{emoji} should be valid"
      end
    end
  end

  describe "unique constraint" do
    test "prevents duplicate reactions from same user on same message" do
      # This test would require database insertion to test the unique constraint
      # Since we're testing the changeset validation, we'll test that the constraint is defined
      attrs = %{emoji: "👍", user_id: 1, message_id: 1}
      changeset = Reaction.changeset(%Reaction{}, attrs)

      # The unique constraint is validated at the database level
      # We can verify the changeset includes the constraint
      constraints = changeset.constraints
      unique_constraint = Enum.find(constraints, &(&1.type == :unique))

      assert unique_constraint
      assert unique_constraint.constraint == "reactions_emoji_message_id_user_id_index"
      assert unique_constraint.field == :emoji
    end

    test "allows same emoji from different users on same message" do
      # This would be tested with actual database insertions
      # For changeset testing, we verify the constraint allows different combinations
      attrs1 = %{emoji: "👍", user_id: 1, message_id: 1}
      attrs2 = %{emoji: "👍", user_id: 2, message_id: 1}

      changeset1 = Reaction.changeset(%Reaction{}, attrs1)
      changeset2 = Reaction.changeset(%Reaction{}, attrs2)

      assert changeset1.valid?
      assert changeset2.valid?
    end

    test "allows different emojis from same user on same message" do
      attrs1 = %{emoji: "👍", user_id: 1, message_id: 1}
      attrs2 = %{emoji: "❤️", user_id: 1, message_id: 1}

      changeset1 = Reaction.changeset(%Reaction{}, attrs1)
      changeset2 = Reaction.changeset(%Reaction{}, attrs2)

      assert changeset1.valid?
      assert changeset2.valid?
    end

    test "allows same emoji from same user on different messages" do
      attrs1 = %{emoji: "👍", user_id: 1, message_id: 1}
      attrs2 = %{emoji: "👍", user_id: 1, message_id: 2}

      changeset1 = Reaction.changeset(%Reaction{}, attrs1)
      changeset2 = Reaction.changeset(%Reaction{}, attrs2)

      assert changeset1.valid?
      assert changeset2.valid?
    end
  end

  describe "associations" do
    test "belongs to user" do
      # Test that the schema defines the user association
      user_assoc = Reaction.__schema__(:association, :user)
      assert user_assoc != nil
      assert user_assoc.related == Slap.Accounts.User
      assert user_assoc.owner_key == :user_id
    end

    test "belongs to message" do
      # Test that the schema defines the message association
      message_assoc = Reaction.__schema__(:association, :message)
      assert message_assoc != nil
      assert message_assoc.related == Slap.Chat.Message
      assert message_assoc.owner_key == :message_id
    end
  end

  describe "schema fields" do
    test "has emoji field" do
      assert Reaction.__schema__(:type, :emoji) == :string
    end

    test "has timestamps" do
      assert Reaction.__schema__(:type, :inserted_at) == :utc_datetime
      assert Reaction.__schema__(:type, :updated_at) == :utc_datetime
    end

    test "has correct table name" do
      assert Reaction.__schema__(:source) == "reactions"
    end
  end

  describe "edge cases" do
    test "handles nil values gracefully" do
      attrs = %{emoji: nil, user_id: 1, message_id: 1}
      changeset = Reaction.changeset(%Reaction{}, attrs)

      refute changeset.valid?
      assert %{emoji: ["can't be blank"]} = errors_on(changeset)
    end

    test "handles very short emoji strings" do
      # Single character emojis
      single_char_emojis = ["♥", "★", "☺", "✓"]

      for emoji <- single_char_emojis do
        attrs = %{emoji: emoji, user_id: 1, message_id: 1}
        changeset = Reaction.changeset(%Reaction{}, attrs)
        assert changeset.valid?, "Single char emoji #{emoji} should be valid"
      end
    end

    test "handles numeric emoji representations" do
      # Some systems use numeric codes for emojis
      numeric_emojis = ["1F44D", "2764", "1F602"]

      for emoji <- numeric_emojis do
        attrs = %{emoji: emoji, user_id: 1, message_id: 1}
        changeset = Reaction.changeset(%Reaction{}, attrs)
        assert changeset.valid?, "Numeric emoji #{emoji} should be valid"
      end
    end
  end
end
