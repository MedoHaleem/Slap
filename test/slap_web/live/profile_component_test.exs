defmodule SlapWeb.ProfileComponentTest do
  use SlapWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Slap.Accounts
  alias Slap.Chat

  setup [:register_and_log_in_user, :create_room]

  describe "Profile component" do
    test "renders profile component with user data", %{conn: conn, user: user, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Check that the profile component is rendered (looking for the profile heading)
      assert view
             |> element("h2", "Profile")
             |> has_element?()

      # Check that the username is displayed
      assert render(view) =~ user.username
    end

    test "closes profile component when close button is clicked", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Check that the profile component is rendered (looking for the profile heading)
      assert view
             |> element("h2", "Profile")
             |> has_element?()

      # Click the close button
      view
      |> element("button[phx-click='close-profile']")
      |> render_click()

      # Check that the profile component is no longer rendered (looking for the profile heading)
      refute view
             |> element("h2", "Profile")
             |> has_element?()
    end
  end

  describe "Avatar upload" do
    test "accepts valid image files", %{conn: conn, user: user, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Create a test image content (small PNG)
      png_content = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
      filename = "test-avatar.png"

      upload =
        file_input(view, "form[phx-submit='submit-avatar']", :avatar, [
          %{
            name: filename,
            content: png_content,
            type: "image/png"
          }
        ])

      render_upload(upload, filename)

      # Submit the form to save the avatar
      view
      |> element("form[phx-submit='submit-avatar']")
      |> render_submit(%{})

      # Verify the avatar was saved
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.avatar_path != nil
      assert String.ends_with?(updated_user.avatar_path, ".png")
    end

    test "rejects invalid file types", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Try to upload a non-image file
      invalid_content = "This is not an image file"
      filename = "test-file.txt"

      upload =
        file_input(view, "form[phx-submit='submit-avatar']", :avatar, [
          %{
            name: filename,
            content: invalid_content,
            type: "text/plain"
          }
        ])

      render_upload(upload, filename)

      # The profile component doesn't display error messages like the message form component does
      # So we just check that the live preview is not shown (which would indicate a successful upload)
      refute view |> element(".live-img-preview") |> has_element?()
    end

    test "handles files that are too large", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Try to upload a file that's too large (exceeds 2MB limit)
      large_content = String.duplicate("A", 2_100_000)  # 2.1MB
      filename = "large-image.jpg"

      upload =
        file_input(view, "form[phx-submit='submit-avatar']", :avatar, [
          %{
            name: filename,
            content: large_content,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, filename)

      # The profile component doesn't display error messages like the message form component does
      # So we just check that the live preview is not shown (which would indicate a successful upload)
      refute view |> element(".live-img-preview") |> has_element?()
    end

    test "generates unique filenames for avatar uploads", %{conn: conn, user: user, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Create a test image content (small PNG)
      png_content = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
      filename = "test-avatar.png"

      # Upload the same file twice
      upload1 =
        file_input(view, "form[phx-submit='submit-avatar']", :avatar, [
          %{
            name: filename,
            content: png_content,
            type: "image/png"
          }
        ])

      render_upload(upload1, filename)

      # Submit the form to save the first avatar
      view
      |> element("form[phx-submit='submit-avatar']")
      |> render_submit(%{})

      first_avatar_path = Accounts.get_user!(user.id).avatar_path

      # Click to open profile again (it might have closed)
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Upload the same file again
      upload2 =
        file_input(view, "form[phx-submit='submit-avatar']", :avatar, [
          %{
            name: filename,
            content: png_content,
            type: "image/png"
          }
        ])

      render_upload(upload2, filename)

      # Submit the form to save the second avatar
      view
      |> element("form[phx-submit='submit-avatar']")
      |> render_submit(%{})

      second_avatar_path = Accounts.get_user!(user.id).avatar_path

      # Verify the avatar paths are different (unique filenames)
      assert first_avatar_path != second_avatar_path
      assert String.ends_with?(first_avatar_path, ".png")
      assert String.ends_with?(second_avatar_path, ".png")
    end

    test "displays current avatar if present", %{conn: conn, user: user, room: room} do
      # Set an avatar path for the user
      avatar_path = "/uploads/avatars/test-avatar-#{System.unique_integer()}.png"
      {:ok, _user} = Accounts.save_user_avatar_path(user, avatar_path)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      # Click to open profile
      view
      |> element("a[phx-click='show-profile']")
      |> render_click()

      # Check that the current avatar is displayed (using the user_avatar component)
      # The user_avatar component renders an img tag with data-user-avatar-id attribute
      assert view
             |> element("img[data-user-avatar-id='#{user.id}']")
             |> has_element?()
    end
  end

  # Helper function to create a test room
  defp create_room(%{user: user}) do
    {:ok, room} = Chat.create_room(%{name: "test-room", user_id: user.id})
    %{room: room}
  end
end
