defmodule SlapWeb.VoiceChatLiveTest do
  use SlapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slap.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture(%{username: "TestUser"})
    target_user = user_fixture(%{username: "TargetUser"})

    conn = log_in_user(conn, user)

    %{
      conn: conn,
      user: user,
      target_user: target_user
    }
  end

  describe "VoiceChatLive" do
    test "mounts successfully", %{conn: conn, target_user: target_user} do
      {:ok, _view, html} = live(conn, ~p"/voice-chat/#{target_user.id}")

      assert html =~ "Voice Chat"
      assert html =~ target_user.username
    end

    test "mounts with accepted_call parameter", %{conn: conn, target_user: target_user} do
      {:ok, _view, html} = live(conn, ~p"/voice-chat/#{target_user.id}?accepted_call=true")

      assert html =~ "Voice Chat"
      assert html =~ target_user.username
    end

    test "handles request_call event", %{conn: conn, target_user: target_user} do
      {:ok, view, _html} = live(conn, ~p"/voice-chat/#{target_user.id}")

      # Click the start call button
      view
      |> element("button", "Start Call")
      |> render_click()

      # Should not crash and should update the view
      html = render(view)
      assert html =~ "Voice Chat"
    end

    test "handles update_status event", %{conn: conn, target_user: target_user} do
      {:ok, view, _html} = live(conn, ~p"/voice-chat/#{target_user.id}")

      # Send update_status event
      view
      |> render_hook("update_status", %{"status" => "connected"})

      # Should not crash
      html = render(view)
      assert html =~ "Voice Chat"
    end

    test "handles signal event", %{conn: conn, target_user: target_user} do
      {:ok, view, _html} = live(conn, ~p"/voice-chat/#{target_user.id}")

      # Send signal event
      signal_data = %{"type" => "offer", "sdp" => "test_sdp"}

      view
      |> render_hook("signal", %{"signal" => signal_data})

      # Should not crash
      html = render(view)
      assert html =~ "Voice Chat"
    end
  end
end
