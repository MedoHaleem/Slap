defmodule SlapWeb.MessageSearchLiveTest do
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
    message1 = message_fixture(room, user, %{body: "Hello world, this is a test message"})
    message2 = message_fixture(room, user, %{body: "Another message with different content"})
    message3 = message_fixture(room, user, %{body: "This message contains the word test"})

    conn = log_in_user(conn, user)

    %{
      conn: conn,
      user: user,
      room: room,
      message1: message1,
      message2: message2,
      message3: message3
    }
  end

  describe "Search page" do
    test "renders search page", %{conn: conn, room: room} do
      {:ok, view, html} = live(conn, ~p"/search/#{room}")

      assert html =~ "Search Messages in #{room.name}"
      assert html =~ "Enter search terms"
      assert has_element?(view, "form")
      assert has_element?(view, "input[name='query']")
    end

    test "shows initial state without search query", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/search/#{room}")

      assert html =~ "Enter a search query to find messages"
      refute html =~ "Search Results"
    end
  end

  describe "Search functionality" do
    test "performs search and displays results", %{conn: conn, room: room, message1: message1} do
      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Perform search
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      # Check results are displayed
      html = render(view)
      assert html =~ "Search Results"
      assert html =~ "results" # Check that results count is shown
      # Check that at least one message is displayed
      assert html =~ "Hello world" or html =~ "Another message" or html =~ "This message contains"
    end

    test "handles empty search query", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Submit empty search
      view
      |> form("form", %{query: ""})
      |> render_submit()

      # Should clear results
      html = render(view)
      refute html =~ "Search Results"
      assert html =~ "Enter a search query"
    end

    test "handles search with no results", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search for non-existent term
      view
      |> form("form", %{query: "nonexistent"})
      |> render_submit()

      # Should show no results message
      html = render(view)
      assert html =~ "Search Results"
      assert html =~ "No messages found"
    end

    test "highlights search terms in results", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search for "test"
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      # Check that search terms are highlighted
      html = render(view)
      assert html =~ "<mark class=\"bg-yellow-200 text-yellow-800 px-1 rounded\">test</mark>"
    end
  end

  describe "Pagination" do
    test "shows pagination for many results", %{conn: conn, room: room, user: user} do
      # Create many messages to trigger pagination
      for i <- 1..25 do
        message_fixture(room, user, %{body: "Message #{i} with test content"})
      end

      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search for "test"
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      # Should show pagination
      html = render(view)
      assert html =~ "Page 1"
      assert html =~ "Next"
    end

    test "navigates to next page", %{conn: conn, room: room, user: user} do
      # Create many messages
      for i <- 1..25 do
        message_fixture(room, user, %{body: "Message #{i} with test content"})
      end

      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search and go to next page
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      view
      |> element("button", "Next")
      |> render_click()

      # Should be on page 2
      html = render(view)
      assert html =~ "Page 2"
      assert html =~ "Previous"
    end

    test "navigates to previous page", %{conn: conn, room: room, user: user} do
      # Create many messages
      for i <- 1..25 do
        message_fixture(room, user, %{body: "Message #{i} with test content"})
      end

      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search and go to next page, then back
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      view
      |> element("button", "Next")
      |> render_click()

      view
      |> element("button", "Previous")
      |> render_click()

      # Should be back on page 1
      html = render(view)
      assert html =~ "Page 1"
    end
  end

  describe "Message display" do
    test "shows message metadata", %{conn: conn, room: room, message1: message1, user: user} do
      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search for content
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      # Check message metadata is displayed
      html = render(view)
      assert html =~ user.username
      assert html =~ "View in context"
    end

    test "links to view message in context", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/search/#{room}")

      # Search for content
      view
      |> form("form", %{query: "test"})
      |> render_submit()

      # Check link exists
      assert has_element?(view, "a", "View in context")
    end
  end
end
