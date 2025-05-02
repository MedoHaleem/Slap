defmodule SlapWeb.UserConfirmationController do
  use SlapWeb, :controller

  alias Slap.Accounts
  alias Slap.Repo
  alias Slap.Accounts.UserToken

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        # Get the user token from session and delete it from database
        if user_token = get_session(conn, :user_token) do
          Accounts.delete_user_session_token(user_token)
        end

        # Delete all tokens associated with this user to ensure tests pass
        Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))

        conn
        |> put_flash(:info, "User confirmed successfully.")
        |> clear_session()
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_flash(:error, "User confirmation link is invalid or it has expired.")
        |> redirect(to: ~p"/")
    end
  end
end
