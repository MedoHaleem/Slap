defmodule SlapWeb.ChatRoomLive.MessageFormComponent do
  use SlapWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="h-12 bg-white px-4 pb-4">
      <.form
        id="new-message-form"
        for={@form}
        phx-change="validate-message"
        phx-submit="submit-message"
        phx-target={@myself}
        class="flex items-center border-2 border-slate-300 rounded-sm p-1"
      >
        <textarea
          class="grow text-sm px-3 border-l border-slate-300 mx-1 resize-none"
          cols=""
          id="chat-message-textarea"
          name={@form[:body].name}
          placeholder={"Message ##{@room.name}"}
          phx-debounce
          phx-hook="ChatMessageTextArea"
          rows="1"
        >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>

        <button class="shrink flex items-center justify-center h-6 w-6 rounded hover:bg-slate-200">
          <.icon name="hero-paper-airplane" class="h-4 w-4" />
        </button>
      </.form>
    </div>
    """
  end

  def handle_event("validate-message", %{"message" => message_params}, socket) do
    changeset = Slap.Chat.change_message(%Slap.Chat.Message{}, message_params)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("submit-message", %{"message" => message_params}, socket) do
    %{current_user: current_user, room: room} = socket.assigns

    case Slap.Chat.create_message(room, message_params, current_user) do
      {:ok, _message} ->
        changeset = Slap.Chat.change_message(%Slap.Chat.Message{})
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
