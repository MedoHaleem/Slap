defmodule Slap.Chat.ConversationParticipantTest do
  use Slap.DataCase, async: true

  alias Slap.Chat.ConversationParticipant

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{conversation_id: 1, user_id: 1}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      assert changeset.valid?
      assert changeset.changes.conversation_id == 1
      assert changeset.changes.user_id == 1
    end

    test "valid changeset with all fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs = %{conversation_id: 1, user_id: 1, last_read_at: now}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      assert changeset.valid?
      assert changeset.changes.last_read_at == now
    end

    test "invalid changeset missing conversation_id" do
      attrs = %{user_id: 1}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      refute changeset.valid?
      assert %{conversation_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset missing user_id" do
      attrs = %{conversation_id: 1}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts nil last_read_at" do
      attrs = %{conversation_id: 1, user_id: 1, last_read_at: nil}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid last_read_at datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs = %{conversation_id: 1, user_id: 1, last_read_at: now}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      assert changeset.valid?
    end
  end

  describe "associations" do
    test "belongs to conversation" do
      conversation_assoc = ConversationParticipant.__schema__(:association, :conversation)
      assert conversation_assoc != nil
      assert conversation_assoc.related == Slap.Chat.Conversation
      assert conversation_assoc.owner_key == :conversation_id
    end

    test "belongs to user" do
      user_assoc = ConversationParticipant.__schema__(:association, :user)
      assert user_assoc != nil
      assert user_assoc.related == Slap.Accounts.User
      assert user_assoc.owner_key == :user_id
    end
  end

  describe "schema fields" do
    test "has last_read_at field" do
      assert ConversationParticipant.__schema__(:type, :last_read_at) == :utc_datetime
    end

    test "has timestamps" do
      assert ConversationParticipant.__schema__(:type, :inserted_at) == :utc_datetime
      assert ConversationParticipant.__schema__(:type, :updated_at) == :utc_datetime
    end

    test "has correct table name" do
      assert ConversationParticipant.__schema__(:source) == "conversation_participants"
    end
  end

  describe "unique constraints" do
    test "unique constraint is defined for user_id and conversation_id" do
      attrs = %{conversation_id: 1, user_id: 1}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      constraints = changeset.constraints
      unique_constraint = Enum.find(constraints, &(&1.type == :unique))

      assert unique_constraint

      assert unique_constraint.constraint ==
               "conversation_participants_conversation_id_user_id_index"
    end

    test "allows same user in different conversations" do
      attrs1 = %{conversation_id: 1, user_id: 1}
      attrs2 = %{conversation_id: 2, user_id: 1}

      changeset1 = ConversationParticipant.changeset(%ConversationParticipant{}, attrs1)
      changeset2 = ConversationParticipant.changeset(%ConversationParticipant{}, attrs2)

      assert changeset1.valid?
      assert changeset2.valid?
    end

    test "allows different users in same conversation" do
      attrs1 = %{conversation_id: 1, user_id: 1}
      attrs2 = %{conversation_id: 1, user_id: 2}

      changeset1 = ConversationParticipant.changeset(%ConversationParticipant{}, attrs1)
      changeset2 = ConversationParticipant.changeset(%ConversationParticipant{}, attrs2)

      assert changeset1.valid?
      assert changeset2.valid?
    end
  end

  describe "edge cases" do
    test "handles nil values gracefully" do
      attrs = %{conversation_id: nil, user_id: nil}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      refute changeset.valid?
      assert %{conversation_id: ["can't be blank"]} = errors_on(changeset)
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "handles invalid datetime for last_read_at" do
      invalid_datetime = "not-a-datetime"
      attrs = %{conversation_id: 1, user_id: 1, last_read_at: invalid_datetime}

      # This should handle the invalid input gracefully
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      # The changeset should be invalid due to invalid datetime
      refute changeset.valid?
      assert %{last_read_at: ["is invalid"]} = errors_on(changeset)
    end

    test "handles future datetime for last_read_at" do
      future_datetime =
        DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      attrs = %{conversation_id: 1, user_id: 1, last_read_at: future_datetime}

      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      # The changeset should be valid - business logic for handling future dates
      # should be implemented at the context level
      assert changeset.valid?
    end

    test "handles zero values for foreign keys" do
      attrs = %{conversation_id: 0, user_id: 0}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      refute changeset.valid?

      assert %{
               user_id: ["must be greater than 0"],
               conversation_id: ["must be greater than 0"]
             } = errors_on(changeset)
    end

    test "handles negative values for foreign keys" do
      attrs = %{conversation_id: -1, user_id: -1}
      changeset = ConversationParticipant.changeset(%ConversationParticipant{}, attrs)

      refute changeset.valid?

      assert %{
               user_id: ["must be greater than 0"],
               conversation_id: ["must be greater than 0"]
             } = errors_on(changeset)
    end
  end
end
