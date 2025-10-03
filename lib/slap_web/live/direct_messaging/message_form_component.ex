defmodule SlapWeb.DirectMessaging.MessageFormComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border-t border-gray-200 bg-white p-4">
      <.form for={@message_form} phx-submit="send_message" phx-target={@myself} class="flex space-x-4">
        <input
          type="text"
          name="message[body]"
          placeholder="Type a message..."
          class="flex-1 border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <.primary_button type="submit">Send</.primary_button>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    current_user = socket.assigns.current_user
    conversation = socket.assigns.conversation

    case Slap.DirectMessaging.send_direct_message(conversation, %{body: body}, current_user) do
      {:ok, message} ->
        send(self(), {:new_message, message})
        {:reply, %{message_form: to_form(%{"body" => ""})}, socket}

      {:error, _changeset} ->
        {:reply, %{error: "Failed to send message"}, socket}
    end
  end
end
