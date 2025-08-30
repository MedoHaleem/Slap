defmodule SlapWeb.MessageSearchLive do
  use SlapWeb, :live_view
  alias Slap.Chat

  def mount(_params, _session, socket) do
    socket
    |> assign(search_query: nil, search_results: [], search_count: 0, page: 1, per_page: 20)
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
      <h1 class="text-xl font-bold mb-4">Search Messages in {@room.name}</h1>

      <form phx-change="search" phx-submit="search" class="mb-6">
        <div class="flex gap-2">
          <input
            type="text"
            name="query"
            value={@search_query || ""}
            placeholder="Enter search terms..."
            class="flex-1 p-2 border rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            autocomplete="off"
          />
          <button
            type="submit"
            class="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-md transition-colors"
          >
            Search
          </button>
        </div>
      </form>

      <%= if @search_query do %>
        <div class="mb-4">
          <div class="flex justify-between items-center mb-2">
            <h2 class="text-lg font-semibold">
              Search Results
              <%= if @search_count > 0 do %>
                <span class="text-sm font-normal text-gray-500">({@search_count} results)</span>
              <% end %>
            </h2>

            <%= if @search_count > @per_page do %>
              <div class="flex gap-2">
                <%= if @page > 1 do %>
                  <button
                    phx-click="previous_page"
                    class="px-3 py-1 text-sm border rounded-md hover:bg-gray-50"
                  >
                    Previous
                  </button>
                <% end %>

                <span class="px-3 py-1 text-sm text-gray-600">
                  Page {@page}
                </span>

                <%= if length(@search_results) == @per_page do %>
                  <button
                    phx-click="next_page"
                    class="px-3 py-1 text-sm border rounded-md hover:bg-gray-50"
                  >
                    Next
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>

          <%= if @search_count == 0 do %>
            <div class="text-center py-8 text-gray-500">
              <p>No messages found matching "{@search_query}"</p>
            </div>
          <% else %>
            <div class="space-y-3">
              <%= for message <- @search_results do %>
                <div class="p-4 bg-white rounded-lg shadow-sm border border-gray-200 hover:shadow-md transition-shadow">
                  <div class="flex items-start justify-between mb-2">
                    <div class="flex items-center">
                      <span class="font-medium text-gray-900">{message.user.username}</span>
                      <%= if Map.get(message, :type) == :reply do %>
                        <span class="ml-2 px-2 py-1 text-xs bg-purple-100 text-purple-800 rounded-full">
                          In Thread
                        </span>
                      <% end %>

                      <span class="text-gray-500 text-sm ml-3">
                        {Calendar.strftime(message.inserted_at, "%b %d, %Y at %H:%M")}
                      </span>
                    </div>

                   <.link
                     navigate={
                       if Map.get(message, :type) == :reply,
                         do:
                           ~p"/rooms/#{@room}?thread=#{message.parent_message_id}&highlight=#{message.id}",
                         else: ~p"/rooms/#{@room}?highlight=#{message.id}"
                     }
                     class="text-blue-500 hover:text-blue-700 text-sm"
                   >
                     View in context
                   </.link>
                  </div>

                  <div class="text-gray-700 leading-relaxed">
                    {raw(highlight_search_terms(message.body, @search_query))}
                    <%= if Map.get(message, :type) == :reply do %>
                      <div class="mt-2 text-sm text-gray-500">
                        <em>Reply to: {String.slice(message.parent_message.body, 0..50)}...</em>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-12 text-gray-500">
          <p>Enter a search query to find messages in {@room.name}</p>
        </div>
      <% end %>
    </div>
    """
  end

  def handle_event("search", %{"query" => query}, socket) do
    trimmed_query = String.trim(query)

    if trimmed_query == "" do
      {:noreply, assign(socket, search_results: [], search_query: nil, search_count: 0, page: 1)}
    else
      results =
        Chat.search_messages(socket.assigns.room.id, trimmed_query,
          limit: socket.assigns.per_page,
          include_threads: true
        )

      total_count = Chat.count_search_results(socket.assigns.room.id, trimmed_query)

      {:noreply,
       assign(socket,
         search_results: results,
         search_query: trimmed_query,
         search_count: total_count,
         page: 1
       )}
    end
  end

  def handle_event("next_page", _, socket) do
    page = socket.assigns.page + 1
    offset = (page - 1) * socket.assigns.per_page
    query = socket.assigns.search_query

    results =
      Chat.search_messages(
        socket.assigns.room.id,
        query,
        limit: socket.assigns.per_page,
        offset: offset,
        include_threads: true
      )

    {:noreply, assign(socket, search_results: results, page: page)}
  end

  def handle_event("previous_page", _, socket) do
    page = max(socket.assigns.page - 1, 1)
    offset = (page - 1) * socket.assigns.per_page
    query = socket.assigns.search_query

    results =
      Chat.search_messages(
        socket.assigns.room.id,
        query,
        limit: socket.assigns.per_page,
        offset: offset,
        include_threads: true
      )

    {:noreply, assign(socket, search_results: results, page: page)}
  end

  # Helper function to highlight search terms
  defp highlight_search_terms(text, query) do
    if query && query != "" do
      # Escape special regex characters in the query
      escaped_query = Regex.escape(query)

      # Create regex with word boundaries to match whole words only
      regex = ~r/#{escaped_query}/i

      # Replace matches with highlighted span
      String.replace(text, regex, &highlight_match/1)
    else
      text
    end
  end

  defp highlight_match(match) do
    "<mark class=\"bg-yellow-200 text-yellow-800 px-1 rounded\">#{match}</mark>"
  end
end
