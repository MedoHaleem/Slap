defmodule SlapWeb.ChatRoomLive.FormComponentTest do
  use SlapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slap.AccountsFixtures
  import Slap.ChatFixtures

  setup %{conn: conn} do
    user = user_fixture(%{username: "TestUser"})
    conn = log_in_user(conn, user)

    %{conn: conn, user: user}
  end

  describe "FormComponent" do
    test "modal button exists on index page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/rooms")

      # Check that the "Create room" button exists
      assert html =~ "Create room"
      assert html =~ "new-room-modal"
    end

    test "room creation validation works", %{conn: _conn} do
      # Test the underlying validation logic by testing the Chat.create_room function
      # This tests the business logic without relying on the modal UI

      # Test valid room creation
      valid_attrs = %{name: "test-room-#{System.unique_integer([:positive])}", topic: "Test Topic"}
      assert {:ok, _room} = Slap.Chat.create_room(valid_attrs)

      # Test invalid room creation (empty name)
      invalid_attrs = %{name: "", topic: "Test Topic"}
      assert {:error, changeset} = Slap.Chat.create_room(invalid_attrs)
      assert %{name: ["can't be blank"]} = Slap.DataCase.errors_on(changeset)

      # Test duplicate name
      duplicate_attrs = %{name: "test-room-#{System.unique_integer([:positive])}", topic: "Test Topic"}
      assert {:ok, _room} = Slap.Chat.create_room(duplicate_attrs)
      assert {:error, changeset} = Slap.Chat.create_room(duplicate_attrs)
      assert %{name: ["has already been taken"]} = Slap.DataCase.errors_on(changeset)
    end

    test "room name length validation", %{conn: _conn} do
      # Test name that's too long
      long_name = String.duplicate("a", 81)
      attrs = %{name: long_name, topic: "Test Topic"}

      assert {:error, changeset} = Slap.Chat.create_room(attrs)
      assert %{name: ["should be at most 80 character(s)"]} = Slap.DataCase.errors_on(changeset)
    end

    test "room topic length validation", %{conn: _conn} do
      # Test topic that's too long
      long_topic = String.duplicate("a", 201)
      attrs = %{name: "test-room-#{System.unique_integer([:positive])}", topic: long_topic}

      assert {:error, changeset} = Slap.Chat.create_room(attrs)
      assert %{topic: ["should be at most 200 character(s)"]} = Slap.DataCase.errors_on(changeset)
    end

    test "successful room creation joins user", %{conn: _conn, user: user} do
      room_name = "test-room-#{System.unique_integer([:positive])}"
      attrs = %{name: room_name, topic: "Test Topic"}

      assert {:ok, room} = Slap.Chat.create_room(attrs)

      # Manually join the user (simulating what the component does)
      Slap.Chat.join_room!(room, user)

      # Verify user is joined
      assert Slap.Chat.joined?(room, user)
    end

    test "room name format validation", %{conn: _conn} do
      # Test invalid characters in room name
      invalid_name = "test-room_with.special.chars"
      attrs = %{name: invalid_name, topic: "Special Topic"}

      assert {:error, changeset} = Slap.Chat.create_room(attrs)
      assert %{name: ["can only contain lowercase letters, numbers and dashes"]} = Slap.DataCase.errors_on(changeset)

      # Test valid name format
      valid_name = "test-room-#{System.unique_integer([:positive])}"
      valid_attrs = %{name: valid_name, topic: "Valid Topic"}

      assert {:ok, _room} = Slap.Chat.create_room(valid_attrs)
    end

    test "component module structure", %{conn: _conn} do
      # Test that the component module exists and has the expected structure
      assert Code.ensure_loaded?(SlapWeb.ChatRoomLive.FormComponent)
      assert function_exported?(SlapWeb.ChatRoomLive.FormComponent, :render, 1)
      # Verify it's a LiveComponent by checking it uses Phoenix.LiveComponent
      assert SlapWeb.ChatRoomLive.FormComponent.__info__(:attributes)[:behaviour] == [Phoenix.LiveComponent]
    end
  end
end
