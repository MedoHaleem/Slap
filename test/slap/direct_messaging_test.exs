defmodule Slap.DirectMessagingTest do
  use Slap.DataCase, async: true

  alias Slap.DirectMessaging
  alias Slap.Accounts.User
  alias Slap.Chat.{Conversation, DirectMessage, ConversationParticipant}

  import Slap.AccountsFixtures
  import Slap.DirectMessagingFixtures

  describe "conversations" do
    test "create_conversation/1 with valid data creates a conversation" do
      attrs = valid_conversation_attributes()
      assert {:ok, %Conversation{} = conversation} = DirectMessaging.create_conversation(attrs)
      assert conversation.title == attrs.title
    end

    test "create_conversation/1 with invalid data returns error changeset" do
      attrs = %{title: ""}
      assert {:error, %Ecto.Changeset{}} = DirectMessaging.create_conversation(attrs)
    end

    test "create_conversation_with_participants/2 creates conversation with participants" do
      user1 = user_fixture()
      user2 = user_fixture()
      attrs = valid_conversation_attributes()

      assert {:ok, %Conversation{} = conversation} =
               DirectMessaging.create_conversation_with_participants(attrs, [user1.id, user2.id])

      # Check that conversation was created
      assert conversation.title == attrs.title

      # Check that participants were added
      participants = DirectMessaging.list_conversation_participants(conversation.id)
      assert length(participants) == 2

      participant_ids = Enum.map(participants, & &1.user_id)
      assert user1.id in participant_ids
      assert user2.id in participant_ids
    end

    test "get_conversation!/1 returns the conversation with given id" do
      conversation = conversation_fixture()
      assert DirectMessaging.get_conversation!(conversation.id) == conversation
    end

    test "get_conversation!/1 with invalid id raises error" do
      assert_raise Ecto.NoResultsError, fn ->
        DirectMessaging.get_conversation!(-1)
      end
    end

    test "list_user_conversations/1 returns conversations for a user" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      # Create conversations
      conversation1 = conversation_with_participants_fixture(user1, user2)
      conversation2 = conversation_with_participants_fixture(user1, user3)
      # This conversation should not appear for user1
      _conversation3 = conversation_with_participants_fixture(user2, user3)

      conversations = DirectMessaging.list_user_conversations(user1.id)

      assert length(conversations) == 2
      conversation_ids = Enum.map(conversations, & &1.id)
      assert conversation1.id in conversation_ids
      assert conversation2.id in conversation_ids
    end

    test "get_conversation_between_users/2 returns conversation between two users" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      conversation = conversation_with_participants_fixture(user1, user2)

      assert DirectMessaging.get_conversation_between_users(user1.id, user2.id) == conversation
      assert DirectMessaging.get_conversation_between_users(user2.id, user1.id) == conversation
      refute DirectMessaging.get_conversation_between_users(user1.id, user3.id)
    end

    test "update_conversation/2 updates the conversation" do
      conversation = conversation_fixture()
      new_title = "Updated Title"

      assert {:ok, %Conversation{} = updated_conversation} =
               DirectMessaging.update_conversation(conversation, %{title: new_title})

      assert updated_conversation.title == new_title
    end

    test "delete_conversation/1 deletes the conversation" do
      conversation = conversation_fixture()
      assert {:ok, %Conversation{}} = DirectMessaging.delete_conversation(conversation)

      assert_raise Ecto.NoResultsError, fn ->
        DirectMessaging.get_conversation!(conversation.id)
      end
    end
  end

  describe "direct messages" do
    setup do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_with_participants_fixture(user1, user2)

      %{user1: user1, user2: user2, conversation: conversation}
    end

    test "send_direct_message/3 with valid data creates a direct message",
         %{conversation: conversation, user1: user} do
      attrs = valid_direct_message_attributes()

      assert {:ok, %DirectMessage{} = direct_message} =
               DirectMessaging.send_direct_message(conversation, attrs, user)

      assert direct_message.body == attrs.body
      assert direct_message.conversation_id == conversation.id
      assert direct_message.user_id == user.id
    end

    test "send_direct_message/3 with empty body returns error",
         %{conversation: conversation, user1: user} do
      attrs = %{body: ""}

      assert {:error, %Ecto.Changeset{}} =
               DirectMessaging.send_direct_message(conversation, attrs, user)
    end

    test "send_direct_message/3 updates conversation last_message_at",
         %{conversation: conversation, user1: user} do
      attrs = valid_direct_message_attributes()
      before_send = DateTime.utc_now() |> DateTime.add(-1, :second)

      {:ok, _direct_message} = DirectMessaging.send_direct_message(conversation, attrs, user)

      updated_conversation = DirectMessaging.get_conversation!(conversation.id)
      assert DateTime.compare(updated_conversation.last_message_at, before_send) == :gt
    end

    test "list_direct_messages/2 returns messages for a conversation",
         %{conversation: conversation, user1: user1, user2: user2} do
      # Create messages
      message1 = direct_message_fixture(conversation, user1)
      message2 = direct_message_fixture(conversation, user2)

      messages = DirectMessaging.list_direct_messages(conversation.id)

      assert length(messages) == 2
      message_ids = Enum.map(messages, & &1.id)
      assert message1.id in message_ids
      assert message2.id in message_ids
    end

    test "list_direct_messages/2 returns messages in chronological order",
         %{conversation: conversation, user1: user1, user2: user2} do
      # Create messages with a small delay
      message1 = direct_message_fixture(conversation, user1)
      :timer.sleep(10)
      message2 = direct_message_fixture(conversation, user2)

      messages = DirectMessaging.list_direct_messages(conversation.id)

      # Messages should be in chronological order (oldest first)
      [first, second] = messages
      assert first.id == message1.id
      assert second.id == message2.id
    end

    test "get_direct_message!/1 returns the direct message with given id",
         %{conversation: conversation, user1: user} do
      direct_message = direct_message_fixture(conversation, user)
      assert DirectMessaging.get_direct_message!(direct_message.id) == direct_message
    end

    test "update_direct_message/2 updates the direct message",
         %{conversation: conversation, user1: user} do
      direct_message = direct_message_fixture(conversation, user)
      new_body = "Updated message body"

      assert {:ok, %DirectMessage{} = updated_message} =
               DirectMessaging.update_direct_message(direct_message, %{body: new_body})

      assert updated_message.body == new_body
    end

    test "delete_direct_message/1 deletes the direct message",
         %{conversation: conversation, user1: user} do
      direct_message = direct_message_fixture(conversation, user)
      assert {:ok, deleted_message} = DirectMessaging.delete_direct_message(direct_message)
      assert deleted_message.id == direct_message.id

      assert_raise Ecto.NoResultsError, fn ->
        DirectMessaging.get_direct_message!(direct_message.id)
      end
    end

    test "search_direct_messages/3 returns matching messages",
         %{conversation: conversation, user1: user1, user2: user2} do
      # Create messages
      direct_message_fixture(conversation, user1, %{body: "Hello world"})
      direct_message_fixture(conversation, user2, %{body: "Good morning"})
      direct_message_fixture(conversation, user1, %{body: "Hello there"})

      results = DirectMessaging.search_direct_messages(conversation.id, "Hello")

      assert length(results) == 2
      assert Enum.all?(results, fn msg -> String.contains?(msg.body, "Hello") end)
    end

    test "search_direct_messages/3 is case insensitive",
         %{conversation: conversation, user1: user} do
      direct_message_fixture(conversation, user, %{body: "Hello WORLD"})

      results = DirectMessaging.search_direct_messages(conversation.id, "hello world")
      assert length(results) == 1

      results = DirectMessaging.search_direct_messages(conversation.id, "HELLO WORLD")
      assert length(results) == 1
    end
  end

  describe "conversation participants" do
    setup do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_with_participants_fixture(user1, user2)

      %{user1: user1, user2: user2, conversation: conversation}
    end

    test "add_participant_to_conversation/3 adds a user to conversation", %{
      conversation: conversation
    } do
      user3 = user_fixture()

      assert {:ok, %ConversationParticipant{}} =
               DirectMessaging.add_participant_to_conversation(conversation, user3.id)

      participants = DirectMessaging.list_conversation_participants(conversation.id)
      assert length(participants) == 3

      participant_ids = Enum.map(participants, & &1.user_id)
      assert user3.id in participant_ids
    end

    test "add_participant_to_conversation/3 with duplicate user returns error", %{
      conversation: conversation,
      user1: user1
    } do
      assert {:error, %Ecto.Changeset{}} =
               DirectMessaging.add_participant_to_conversation(conversation, user1.id)
    end

    test "remove_participant_from_conversation/3 removes a user from conversation", %{
      conversation: conversation,
      user1: user1
    } do
      assert {1, nil} =
               DirectMessaging.remove_participant_from_conversation(conversation, user1.id)

      participants = DirectMessaging.list_conversation_participants(conversation.id)
      assert length(participants) == 1

      participant_ids = Enum.map(participants, & &1.user_id)
      refute user1.id in participant_ids
    end

    test "get_conversation_participant/2 returns participant for user in conversation", %{
      conversation: conversation,
      user1: user1
    } do
      participant =
        DirectMessaging.get_conversation_participant(
          conversation.id,
          user1.id
        )

      assert participant != nil
      assert participant.user_id == user1.id
      assert participant.conversation_id == conversation.id
    end

    test "get_conversation_participant/2 with non-existent user returns nil", %{
      conversation: conversation
    } do
      user3 = user_fixture()

      participant =
        DirectMessaging.get_conversation_participant(
          conversation.id,
          user3.id
        )

      assert participant == nil
    end

    test "mark_conversation_as_read/2 updates last_read_at timestamp", %{
      conversation: conversation,
      user1: user1
    } do
      before_update = DateTime.utc_now() |> DateTime.add(-1, :second)

      assert {:ok, %ConversationParticipant{} = participant} =
               DirectMessaging.mark_conversation_as_read(conversation.id, user1.id)

      assert DateTime.compare(participant.last_read_at, before_update) == :gt
    end

    test "count_unread_messages/2 returns count of unread messages",
         %{conversation: conversation, user1: user1, user2: user2} do
      # Mark conversation as read for user1 first
      {:ok, participant} = DirectMessaging.mark_conversation_read(conversation, user1)

      # Verify that the participant has a last_read_at timestamp
      assert participant.last_read_at != nil

      # Manually set the last_read_at timestamp to a time in the past
      past_time = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(participant, %{last_read_at: past_time})
      |> Slap.Repo.update!()

      # Send a message from user2 (this should be unread)
      direct_message_fixture(conversation, user2)

      # Send another message from user2 (this should also be unread)
      direct_message_fixture(conversation, user2)

      unread_count = DirectMessaging.count_unread_messages(conversation.id, user1.id)
      assert unread_count == 2
    end
  end

  describe "pubsub broadcasting" do
    setup do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_with_participants_fixture(user1, user2)

      # Subscribe to conversation topic
      Phoenix.PubSub.subscribe(Slap.PubSub, "conversation:#{conversation.id}")

      %{user1: user1, user2: user2, conversation: conversation}
    end

    test "send_direct_message/3 broadcasts new message",
         %{conversation: conversation, user1: user} do
      attrs = valid_direct_message_attributes()

      {:ok, direct_message} = DirectMessaging.send_direct_message(conversation, attrs, user)

      # Check if the message was broadcast
      assert_receive {:new_direct_message, ^direct_message}
    end

    test "update_direct_message/2 broadcasts updated message",
         %{conversation: conversation, user1: user} do
      direct_message = direct_message_fixture(conversation, user)
      new_body = "Updated message"

      {:ok, updated_message} =
        DirectMessaging.update_direct_message(direct_message, %{body: new_body})

      # Check if the update was broadcast
      assert_receive {:updated_direct_message, ^updated_message}
    end

    test "delete_direct_message/1 broadcasts message deletion",
         %{conversation: conversation, user1: user} do
      direct_message = direct_message_fixture(conversation, user)

      {:ok, deleted_message} = DirectMessaging.delete_direct_message(direct_message)

      # Check if the deletion was broadcast
      assert_receive {:deleted_direct_message, ^deleted_message}
    end
  end

  describe "edge cases and error handling" do
    test "create_conversation_with_participants/2 with empty participant list returns error" do
      attrs = valid_conversation_attributes()

      assert {:error, %Ecto.Changeset{}} =
               DirectMessaging.create_conversation_with_participants(attrs, [])
    end

    test "create_conversation_with_participants/2 with non-existent user returns error" do
      attrs = valid_conversation_attributes()

      assert {:error, %Ecto.Changeset{}} =
               DirectMessaging.create_conversation_with_participants(attrs, [-1])
    end

    test "send_direct_message/3 with non-existent conversation returns error" do
      user = user_fixture()
      attrs = valid_direct_message_attributes()
      fake_conversation = %Conversation{id: -1}

      assert {:error, %Ecto.Changeset{}} =
               DirectMessaging.send_direct_message(fake_conversation, attrs, user)
    end

    test "send_direct_message/3 with non-existent user returns error" do
      conversation = conversation_fixture()
      attrs = valid_direct_message_attributes()
      fake_user = %User{id: -1}

      assert {:error, %Ecto.Changeset{}} =
               DirectMessaging.send_direct_message(conversation, attrs, fake_user)
    end

    test "search_direct_messages/3 with empty query returns all messages" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_with_participants_fixture(user1, user2)

      # Create messages
      direct_message_fixture(conversation, user1, %{body: "Hello world"})
      direct_message_fixture(conversation, user2, %{body: "Good morning"})

      results = DirectMessaging.search_direct_messages(conversation.id, "")
      assert length(results) == 2
    end

    test "search_direct_messages/3 with special characters handles gracefully" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation = conversation_with_participants_fixture(user1, user2)

      # Create message with special characters
      direct_message_fixture(conversation, user1, %{body: "Special chars: &@#$%"})

      # Search with special characters
      results = DirectMessaging.search_direct_messages(conversation.id, "&@#$%")
      assert length(results) == 1
    end
  end
end
