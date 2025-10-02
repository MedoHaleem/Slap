defmodule SlapWeb.DirectMessaging.GroupSettingsComponent do
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
      <h4 class="text-sm font-medium text-gray-700 mb-2">Conversation Settings</h4>
      <form phx-submit="update_conversation_title" phx-target={@myself} class="space-y-3">
        <div>
          <label class="block text-xs text-gray-600">Conversation Title</label>
          <input
            type="text"
            name="title"
            value={@conversation.title}
            class="w-full text-sm border border-gray-300 rounded px-2 py-1"
          />
        </div>
        <.success_button type="submit">Update Title</.success_button>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("update_conversation_title", %{"title" => title}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    if Authorization.can_manage_conversation?(current_user, conversation) do
      case Slap.DirectMessaging.update_conversation(conversation, %{title: title}) do
        {:ok, updated_conversation} ->
          send(self(), {:conversation_updated, updated_conversation})
          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, Constants.get_error_message(:conversation_update_failed))}
      end
    else
      {:noreply, put_flash(socket, :error, Constants.get_error_message(:insufficient_permissions))}
    end
  end
end
