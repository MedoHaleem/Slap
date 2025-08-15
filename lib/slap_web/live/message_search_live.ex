defmodule SlapWeb.MessageSearchLive do
  use SlapWeb, :live_view
  alias Slap.Chat

  def mount(_params, _session, socket) do
    socket
    |> assign(search_query: nil, search_results: [])
    |> ok()
  end

  def handle_params(%{"room_id" => room_id}, _uri, socket) do
    room = Chat.get_room!(room_id)
    socket
    |> assign(room: room)
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div class="p-4">
      <h1 class="text-xl font-bold mb-4">Search Messages in <%= @room.name %></h1>

      <form phx-change="search" phx-submit="search">
        <input
          type="text"
          name="query"
          value={@search_query || ""}
          placeholder="Enter search terms..."
          class="w-full p-2 border rounded mb-4"
        />
        <button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded">
          Search
        </button>
      </form>

      <div class="mt-4">
        <%= if @search_query do %>
          <h2 class="text-lg font-semibold mb-2">Results</h2>
          <div class="space-y-3">
            <%= for message <- @search_results do %>
              <div class="p-3 bg-white rounded shadow">
                <div class="flex items-center mb-1">
                  <span class="font-medium"><%= message.user.username %></span>
                  <span class="text-gray-500 text-sm ml-2">
                    <%= Calendar.strftime(message.inserted_at, "%b %d, %H:%M") %>
                  </span>
                </div>
                <p><%= message.body %></p>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("search", %{"query" => query}, socket) do
    results = Chat.search_messages(socket.assigns.room.id, query)
    {:noreply, assign(socket, search_results: results, search_query: query)}
  end
end
