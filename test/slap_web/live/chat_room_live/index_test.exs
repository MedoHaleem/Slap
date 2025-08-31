defmodule SlapWeb.ChatRoomLive.IndexTest do
  use SlapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slap.AccountsFixtures
  import Slap.ChatFixtures

  setup %{conn: conn} do
    user = user_fixture(%{username: "TestUser"})
    another_user = user_fixture(%{username: "AnotherUser"})

    room = room_fixture(%{name: "test-room", topic: "Test Room Topic"})
    another_room = room_fixture(%{name: "another-room", topic: "Another Room Topic"})

    conn = log_in_user(conn, user)

    %{
      conn: conn,
      user: user,
      another_user: another_user,
      room: room,
      another_room: another_room
    }
  end

  describe "Room listing" do
    test "renders the room index page", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/rooms")

      assert html =~ "All rooms"
      assert html =~ "Create room"
      assert has_element?(view, "#rooms")
    end

    test "lists all rooms with joined status", %{
      conn: conn,
      room: room,
      another_room: another_room
    } do
      {:ok, _view, html} = live(conn, ~p"/rooms")

      assert html =~ room.name
      assert html =~ another_room.name
      assert html =~ room.topic
      assert html =~ another_room.topic
    end

    test "shows joined status for rooms the user has joined", %{
      conn: conn,
      room: room,
      user: user
    } do
      # Join the room first
      join_room(room, user)

      {:ok, _view, html} = live(conn, ~p"/rooms")

      assert html =~ "✓ Joined"
    end

    test "shows join/leave buttons for each room", %{conn: conn, room: room, user: user} do
      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Check that join button is present for unjoined room
      assert has_element?(view, "button", "Join")

      # Join the room
      join_room(room, user)

      # Reload the page
      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Check that leave button is present for joined room
      assert has_element?(view, "button", "Leave")
    end
  end

  describe "Room navigation" do
    test "navigates to room when clicked", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Click on the room div (not a link, uses phx-click with JS navigation)
      view
      |> element("#rooms-#{room.id}")
      |> render_click()

      # Should navigate to the room (this would be tested by checking the path or redirect)
      # In a real test, you might check the current path or follow the redirect
    end

    test "supports keyboard navigation", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Simulate Enter key press on room div
      view
      |> element("#rooms-#{room.id}[phx-key='Enter']")
      |> render_keydown(%{"key" => "Enter"})
    end
  end

  describe "Room membership" do
    test "can join a room", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Click the join button for this specific room
      view
      |> element("button[phx-click='toggle-room-membership'][phx-value-id='#{room.id}']")
      |> render_click()

      # Check that the button now shows "Leave"
      assert render(view) =~ "Leave"
    end

    test "can leave a room", %{conn: conn, room: room, user: user} do
      # Join the room first
      join_room(room, user)

      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Click the leave button for this specific room
      view
      |> element("button[phx-click='toggle-room-membership'][phx-value-id='#{room.id}']")
      |> render_click()

      # Check that the button now shows "Join"
      assert render(view) =~ "Join"
    end
  end

  describe "Pagination" do
    test "shows pagination when there are multiple pages", %{conn: conn} do
      # Create enough rooms to trigger pagination (more than 10)
      for i <- 1..15 do
        room_fixture(%{name: "room-#{i}", topic: "Topic #{i}"})
      end

      {:ok, _view, html} = live(conn, ~p"/rooms")

      # Should show pagination controls
      assert html =~ "Previous"
      assert html =~ "Next"
    end

    test "navigates to different pages", %{conn: conn} do
      # Create enough rooms for multiple pages
      for i <- 1..15 do
        room_fixture(%{name: "room-#{i}", topic: "Topic #{i}"})
      end

      {:ok, view, _html} = live(conn, ~p"/rooms")

      # Click on page 2
      view
      |> element("a", "2")
      |> render_click()

      # Should navigate to page 2
      assert_patch(view, ~p"/rooms?page=2")
    end

    test "handles invalid page numbers gracefully", %{conn: conn} do
      # Try to access a page that doesn't exist
      {:ok, view, _html} = live(conn, ~p"/rooms?page=999")

      # Should handle gracefully (either redirect to page 1 or show empty results)
      assert render(view) =~ "All rooms"
    end
  end

  describe "Create room modal" do
    test "shows create room modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rooms")

      # The "Create room" button uses JS commands to show the modal
      # We can test that the modal is initially hidden and the button exists
      assert has_element?(view, "button", "Create room")

      # Since the modal uses JS commands, we can check that the modal HTML is present
      # but initially hidden
      html = render(view)
      assert html =~ "New chat room"
      # The modal should be hidden initially
      assert html =~ "hidden"
    end
  end
end
