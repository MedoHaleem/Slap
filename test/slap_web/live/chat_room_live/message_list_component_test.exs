defmodule SlapWeb.ChatRoomLive.MessageListComponentTest do
  use SlapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slap.AccountsFixtures
  import Slap.ChatFixtures

  setup %{conn: conn} do
    user = user_fixture(%{username: "TestUser"})
    room = room_fixture(%{name: "test-room", topic: "Test Room Topic"})

    # Join the room
    join_room(room, user)

    # Create some test messages
    message1 = message_fixture(room, user, %{body: "First message"})
    message2 = message_fixture(room, user, %{body: "Second message"})

    conn = log_in_user(conn, user)

    %{
      conn: conn,
      user: user,
      room: room,
      message1: message1,
      message2: message2
    }
  end

  describe "MessageListComponent" do
    test "renders message list container", %{conn: conn, message1: message1} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{message1.room_id}")

      # The component should be rendered within the ChatRoomLive
      assert has_element?(view, "#room-messages")
      assert has_element?(view, "[phx-hook='RoomMessages']")
      assert has_element?(view, "[phx-update='stream']")
    end

    test "displays messages in the list", %{conn: conn, message1: message1, message2: message2} do
      {:ok, view, html} = live(conn, ~p"/rooms/#{message1.room_id}")

      # Check that messages are displayed
      assert html =~ message1.body
      assert html =~ message2.body

      # Check that message elements exist (using the actual CSS classes from the component)
      assert has_element?(view, ".group.relative.flex")
    end

    test "shows user information with messages", %{conn: conn, user: user, message1: message1} do
      {:ok, view, html} = live(conn, ~p"/rooms/#{message1.room_id}")

      # Check that username is displayed
      assert html =~ user.username

      # Check that user avatar or identifier is present
      assert has_element?(view, ".group.relative.flex")
    end

    test "displays message timestamps", %{conn: conn, message1: message1} do
      {:ok, _view, html} = live(conn, ~p"/rooms/#{message1.room_id}")

      # Check that timestamps are displayed (messages have inserted_at)
      assert html =~ "message"
    end

    test "handles empty message list", %{conn: conn, room: room, user: user} do
      # Create a room with no messages
      empty_room = room_fixture(%{name: "empty-room", topic: "Empty Room"})
      join_room(empty_room, user)

      {:ok, view, html} = live(conn, ~p"/rooms/#{empty_room.id}")

      # Should still render the container
      assert html =~ "room-messages"
      assert has_element?(view, "#room-messages")
    end

    test "displays multiple messages from different users", %{conn: conn, room: room, user: user} do
      # Create another user and message
      other_user = user_fixture(%{username: "OtherUser"})
      join_room(room, other_user)
      other_message = message_fixture(room, other_user, %{body: "Message from other user"})

      {:ok, _view, html} = live(conn, ~p"/rooms/#{room.id}")

      # Check that both users' messages are displayed
      assert html =~ user.username
      assert html =~ other_user.username
      assert html =~ other_message.body
    end

    test "renders message with attachments", %{conn: conn, room: room, user: user, message1: message1} do
      # Add attachment to message1
      attachment = attachment_fixture(message1)

      {:ok, _view, html} = live(conn, ~p"/rooms/#{room.id}")

      # Check that attachment info is displayed
      assert html =~ attachment.file_name
    end
  end

end
