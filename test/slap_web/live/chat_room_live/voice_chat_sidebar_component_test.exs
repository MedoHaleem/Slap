defmodule SlapWeb.ChatRoomLive.VoiceChatSidebarComponentTest do
  use SlapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slap.AccountsFixtures

  setup %{conn: _conn} do
    user = user_fixture(%{username: "TestUser"})
    caller = user_fixture(%{username: "CallerUser"})
    target = user_fixture(%{username: "TargetUser"})

    %{
      user: user,
      caller: caller,
      target: target
    }
  end

  describe "VoiceChatSidebarComponent" do
    test "renders component with init status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "init"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Ready to call"
      assert html =~ "Start Call"
      assert html =~ target.username
    end

    test "renders component with incoming call status", %{user: user, caller: caller} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: user,
        target_user_id: user.id,
        caller: caller,
        call_id: "test-call-123",
        call_status: "incoming"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Incoming call..."
      assert html =~ "Accept"
      assert html =~ "Reject"
      assert html =~ caller.username
    end

    test "renders component with connected status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "connected"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Call connected"
      assert html =~ "End Call"
      assert html =~ "audio-wave"
    end

    test "renders component with error status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "error: Connection failed"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Error: Connection failed"
      assert html =~ "Try Again"
    end

    test "renders component with requesting status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "requesting"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Calling..."
      assert html =~ target.username
    end

    test "renders component with connecting status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "connecting"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Connecting..."
      assert html =~ "End Call"
    end

    test "renders component with ended status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "ended"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Call ended"
      assert html =~ "Close"
    end

    test "renders component with rejected status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "rejected"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Call rejected"
      assert html =~ "Close"
    end

    test "renders component with disconnected status", %{user: user, target: target} do
      assigns = %{
        id: "voice-chat",
        current_user: user,
        target_user: target,
        target_user_id: target.id,
        caller: user,
        call_id: "test-call-123",
        call_status: "disconnected"
      }

      html = render_component(SlapWeb.ChatRoomLive.VoiceChatSidebarComponent, assigns)

      assert html =~ "Voice Call"
      assert html =~ "Call disconnected"
    end
  end
end
