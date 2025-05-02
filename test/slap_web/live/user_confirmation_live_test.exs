defmodule SlapWeb.UserConfirmationLiveTest do
  use SlapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Slap.AccountsFixtures

  alias Slap.Accounts
  alias Slap.Repo

  setup do
    %{user: user_fixture()}
  end

  describe "Confirm user" do
    test "renders confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/confirm/some-token")
      assert html =~ "Confirm Account"
    end

    test "confirms the given token once", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      # First log in the user
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/confirm_account/#{token}")

      # Assert we were redirected to the confirmation controller
      assert {:ok, conn} = result

      # Now follow that redirect to the root page
      assert redirected_to(conn) == ~p"/"

      # Get a new session to confirm the user token is gone
      conn = get(conn, ~p"/")
      refute get_session(conn, :user_token)

      assert Accounts.get_user!(user.id).confirmed_at
      assert Repo.all(Accounts.UserToken) == []

      # when not logged in
      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/confirm_account/#{token}")

      assert {:ok, conn} = result
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "User confirmation link is invalid or it has expired"

      # when logged in
      conn =
        build_conn()
        |> log_in_user(user)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/confirm_account/#{token}")

      assert {:ok, conn} = result
      assert redirected_to(conn) == ~p"/"
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      # First log in the user
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/invalid-token")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/confirm_account/invalid-token")

      assert {:ok, conn} = result
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "User confirmation link is invalid or it has expired"

      refute Accounts.get_user!(user.id).confirmed_at
    end
  end
end
