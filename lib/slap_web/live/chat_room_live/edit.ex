defmodule SlapWeb.ChatRoomLive.Edit do
  use SlapWeb, :live_view
  import SlapWeb.RoomComponents

  alias Slap.Chat

  def render(assigns) do
    ~H"""
    <div class="mx-auto w-96 mt-12">
      <.header>
        {@page_title}
        <:actions>
          <.link
            class="font-normal text-xs text-blue-600 hover:text-blue-700"
            navigate={~p"/rooms/#{@room}"}
          >
            Back
          </.link>
        </:actions>
      </.header>
      <.room_form form={@form} />
    </div>
    """
  end

  def mount(%{"id" => id}, _session, socket) do
    room = Chat.get_room!(id)

    socket =
      if Chat.joined?(room, socket.assigns.current_user) do
        changeset = Chat.change_room(room)

        socket
        |> assign(page_title: "Edit chat room", room: room)
        |> assign_form(changeset)
      else
        socket
        |> put_flash(:error, "Permission denied")
        |> push_navigate(to: ~p"/")
      end

    socket |> ok()
  end

  def handle_event("validate-room", %{"room" => room_params}, socket) do
    changeset =
      socket.assigns.room |> Chat.change_room(room_params) |> Map.put(:action, :validate)

    assign_form(socket, changeset) |> noreply()
  end

  def handle_event("save-room", %{"room" => room_params}, socket) do
    case Chat.update_room(socket.assigns.room, room_params) do
      {:ok, room} ->
        socket
        |> put_flash(:info, "Room updated Successfully")
        |> push_navigate(to: ~p"/rooms/#{room}")
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        assign_form(socket, changeset) |> noreply()
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
