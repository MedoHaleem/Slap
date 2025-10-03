defmodule SlapWeb.DirectMessaging.ParticipantListComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers
  alias Slap.{Constants, Authorization}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-3 border-t border-gray-100 pt-3">
      <h4 class="text-sm font-medium text-gray-700 mb-2">Participants</h4>
      <div class="space-y-2 max-h-32 overflow-y-auto">
        <%= for participant <- @conversation.conversation_participants do %>
          <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
            <div class="flex items-center space-x-2">
              <.user_avatar user={participant.user} size="small" />
              <span class="text-sm text-gray-900">
                {participant.user.username}
              </span>
              <.role_badge role={participant.role} />
            </div>

            <%= if Authorization.can_manage_participants?(@current_user, @conversation) &&
                  participant.user_id != @current_user.id do %>
              <div class="flex items-center space-x-1">
                <select
                  class="text-xs border border-gray-300 rounded px-1 py-0.5"
                  phx-change="promote_participant"
                  phx-value-user-id={participant.user_id}
                  phx-target={@myself}
                >
                  <option value="member" selected={participant.role == "member"}>Member</option>
                  <option value="moderator" selected={participant.role == "moderator"}>
                    Moderator
                  </option>
                  <option value="admin" selected={participant.role == "admin"}>Admin</option>
                </select>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if Authorization.can_invite_to_conversation?(@current_user, @conversation) do %>
        <div class="mt-3">
          <form phx-submit="invite_user" phx-target={@myself} class="flex space-x-2">
            <input
              type="number"
              name="user_id"
              placeholder="User ID to invite"
              class="flex-1 text-sm border border-gray-300 rounded px-2 py-1"
              required
            />
            <.secondary_button type="submit">Invite</.secondary_button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("promote_participant", %{"user_id" => user_id, "role" => new_role}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    case Slap.DirectMessaging.promote_participant(
           conversation,
           String.to_integer(user_id),
           new_role,
           current_user
         ) do
      {:ok, _participant} ->
        # Refresh conversation participants
        updated_conversation =
          Slap.DirectMessaging.get_conversation!(conversation.id)
          |> Slap.Repo.preload(conversation_participants: :user)

        send(self(), {:participants_updated, updated_conversation})
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, Constants.get_error_message(:participant_promotion_failed))}
    end
  end

  @impl true
  def handle_event("invite_user", %{"user_id" => invitee_id}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    case Slap.DirectMessaging.create_conversation_invite(
           conversation,
           String.to_integer(invitee_id),
           current_user
         ) do
      {:ok, _invite} ->
        {:noreply, put_flash(socket, :info, Constants.get_success_message(:invitation_sent))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, Constants.get_error_message(:invitation_send_failed))}
    end
  end
end
