defmodule SlapWeb.ChatRoomLive.JoinRoomComponent do
  use SlapWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="flex justify-around mx-5 mb-5 p-6 bg-slate-100 border-slate-300 border rounded-lg">
      <div class="max-w-3-xl text-center">
        <div class="mb-4">
          <h1 class="text-xl font-semibold">{@room.name}</h1>

          <p :if={@room.topic} class="text-sm mt-1 text-gray-600">{@room.topic}</p>
        </div>

        <div class="flex items-center justify-around">
          <button
            phx-click="join-room"
            class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-600 focus:outline-none focus:ring-2 focus:ring-green-500"
          >
            Join Room
          </button>
        </div>

        <div class="mt-4">
          <.link
            navigate={~p"/rooms"}
            href="#"
            class="text-sm text-slate-500 underline hover:text-slate-600"
          >
            Back to All Rooms
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
