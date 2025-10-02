# Search Functionality

This document provides a comprehensive overview of the search functionality in Slap, including full-text search implementation, search UI, and performance optimizations.

## Overview

The search system allows users to:

- Search within chat room messages
- Search within direct message conversations
- Search across both message types simultaneously
- View search results with context and highlighting
- Navigate through paginated search results
- Search in real-time as they type

## Architecture

### Technology Stack

The search system is built with:

- **PostgreSQL Full-Text Search**: tsvector and tsquery functions
- **Ecto Query**: Database query composition
- **Phoenix LiveView**: Real-time search UI
- **JavaScript Hooks**: Client-side search interactions

### Context Modules

Search functionality is implemented in:

- [`Slap.Chat`](../../lib/slap/chat.ex) - Chat room message search
- [`Slap.DirectMessaging`](../../lib/slap/direct_messaging.ex) - Direct message search
- [`SlapWeb.MessageSearchLive`](../../lib/slap_web/live/message_search_live.ex) - Search UI

## Full-Text Search Implementation

### PostgreSQL Configuration

The database is configured for full-text search with:

```sql
-- Search index for messages
CREATE INDEX messages_search_index 
ON messages 
USING gin(to_tsvector('english', body));

-- Search index for direct messages
CREATE INDEX direct_messages_search_index 
ON direct_messages 
USING gin(to_tsvector('english', body));
```

### Search Query Implementation

#### Chat Room Message Search

```elixir
def search_messages(room_id, query, opts \\ []) do
  # Build the search query
  search_query = build_search_query(query)
  
  Message
  |> join(:inner, [m], u in assoc(m, :user))
  |> where([m, u], m.room_id == ^room_id)
  |> where([m, u], 
    fragment("to_tsvector('english', ?) @@ to_tsquery('english', ?)", m.body, ^search_query))
  |> order_by([m, u], 
    [desc: ts_rank(
      fragment("to_tsvector('english', ?)", m.body), 
      fragment("to_tsquery('english', ?)", ^search_query)
    )])
  |> maybe_preload([:user, :reactions, :attachments])
  |> paginate(opts)
  |> Repo.all()
end
```

#### Direct Message Search

```elixir
def search_direct_messages(conversation_id, query, opts \\ []) do
  search_query = build_search_query(query)
  
  DirectMessage
  |> join(:inner, [dm], u in assoc(dm, :user))
  |> where([dm, u], dm.conversation_id == ^conversation_id)
  |> where([dm, u], 
    fragment("to_tsvector('english', ?) @@ to_tsquery('english', ?)", dm.body, ^search_query))
  |> order_by([dm, u], 
    [desc: ts_rank(
      fragment("to_tsvector('english', ?)", dm.body), 
      fragment("to_tsquery('english', ?)", ^search_query)
    )])
  |> maybe_preload([:user, :reactions, :attachments])
  |> paginate(opts)
  |> Repo.all()
end
```

### Query Building

```elixir
defp build_search_query(query) do
  query
  |> String.trim()
  |> String.split()
  |> Enum.map(&String.replace(&1, ~r/[^\w\s-]/, ""))
  |> Enum.reject(&(&1 == ""))
  |> Enum.map_join(" & ", &"#{&1}:*")
end
```

## Search UI Components

### MessageSearchLive

The main search interface handles:

- Search input with real-time updates
- Result display with highlighting
- Pagination for large result sets
- Context switching between rooms and conversations

```elixir
defmodule SlapWeb.MessageSearchLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:query, "")
      |> assign(:results, [])
      |> assign(:page, 1)
      |> assign(:total_pages, 0)
      |> assign(:search_type, "all")
      |> assign(:room_id, nil)
      |> assign(:conversation_id, nil)
    
    {:ok, socket}
  end
  
  def handle_params(%{"room_id" => room_id}, _uri, socket) do
    socket =
      socket
      |> assign(:room_id, room_id)
      |> assign(:search_type, "room")
      |> perform_search()
    
    {:noreply, socket}
  end
  
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:page, 1)
      |> perform_search()
    
    {:noreply, socket}
  end
  
  def handle_event("next_page", _, socket) do
    socket =
      socket
      |> assign(:page, socket.assigns.page + 1)
      |> perform_search()
    
    {:noreply, socket}
  end
  
  def handle_event("previous_page", _, socket) do
    socket =
      socket
      |> assign(:page, max(1, socket.assigns.page - 1))
      |> perform_search()
    
    {:noreply, socket}
  end
```

### Search Execution

```elixir
defp perform_search(socket) do
  query = String.trim(socket.assigns.query)
  
  results = 
    case {socket.assigns.search_type, String.length(query) > 0} do
      {"room", true} -> 
        search_room_messages(socket.assigns.room_id, query, socket.assigns.page)
      
      {"conversation", true} -> 
        search_conversation_messages(socket.assigns.conversation_id, query, socket.assigns.page)
      
      {"all", true} -> 
        search_all_messages(query, socket.assigns.page)
      
      _ -> 
        []
    end
  
  total_count = count_search_results(query, socket.assigns.search_type)
  total_pages = ceil(total_count / 20) # 20 results per page
  
  socket
  |> assign(:results, results)
  |> assign(:total_pages, total_pages)
  |> assign(:total_count, total_count)
end
```

### Search Template

```elixir
def render(assigns) do
  ~H"""
  <div class="search-container">
    <div class="search-header">
      <h1>Search Messages</h1>
      
      <form phx-change="search" phx-submit="search" class="mt-4">
        <div class="relative">
          <input
            type="text"
            name="query"
            value={@query}
            placeholder="Search messages..."
            class="w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            autocomplete="off"
          />
          <div class="absolute right-2 top-2">
            <.icon name="hero-magnifying-glass" class="w-5 h-5 text-gray-400" />
          </div>
        </div>
      </form>
    </div>
    
    <div class="search-results mt-6">
      <%= if @query != "" do %>
        <div class="results-header mb-4">
          <p class="text-gray-600">
            Found <%= @total_count %> results for "<%= @query %>"
          </p>
        </div>
        
        <div class="results-list space-y-4">
          <%= for result <- @results do %>
            <.search_result result={result} />
          <% end %>
        </div>
        
        <%= if @total_pages > 1 do %>
          <.pagination 
            current_page={@page} 
            total_pages={@total_pages} 
            total_count={@total_count} 
          />
        <% end %>
      <% else %>
        <div class="search-empty">
          <p class="text-gray-500 text-center py-8">
            Enter a search term to find messages
          </p>
        </div>
      <% end %>
    </div>
  </div>
  """
end
```

### Search Result Component

```elixir
defp search_result(assigns) do
  ~H"""
  <div class="search-result p-4 border rounded-lg hover:bg-gray-50">
    <div class="result-header flex items-center justify-between mb-2">
      <div class="flex items-center space-x-2">
        <img 
          src={@result.user.avatar_path || "/images/profile_avatar.png"} 
          class="w-6 h-6 rounded-full"
        />
        <span class="font-medium"><%= @result.user.username %></span>
        <span class="text-gray-500 text-sm">
          <%= result_location(@result) %>
        </span>
      </div>
      <span class="text-gray-500 text-sm">
        <%= message_timestamp(@result) %>
      </span>
    </div>
    
    <div class="result-body">
      <p class="text-gray-800">
        <%= highlight_search_terms(@result.body, @query) %>
      </p>
    </div>
    
    <div class="result-actions mt-2">
      <a 
        href={result_link(@result)} 
        class="text-blue-500 hover:text-blue-700 text-sm"
      >
        View in context
      </a>
    </div>
  </div>
  """
end
```

## Search Highlighting

### Client-side Highlighting

```javascript
// assets/js/utils/messageHighlight.js
export function highlightSearchTerms(text, query) {
  if (!query || query.trim() === '') {
    return text;
  }
  
  const terms = query.trim().split(/\s+/);
  let highlightedText = text;
  
  terms.forEach(term => {
    if (term.length > 0) {
      const regex = new RegExp(`(${escapeRegExp(term)})`, 'gi');
      highlightedText = highlightedText.replace(regex, '<mark>$1</mark>');
    }
  });
  
  return highlightedText;
}

function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
```

### Server-side Highlighting

```elixir
defp highlight_search_terms(text, query) do
  terms = String.split(query, " ", trim: true)
  
  Enum.reduce(terms, text, fn term, acc ->
    if String.length(term) > 0 do
      String.replace(acc, ~r/#{Regex.escape(term)}/i, "<mark>\\0</mark>")
    else
      acc
    end
  end)
end
```

## Real-time Search

### Debounced Search

```javascript
// assets/js/hooks/search.js
const SearchHook = {
  mounted() {
    this.timeout = null;
    this.setupSearch();
  },
  
  setupSearch() {
    const searchInput = this.el.querySelector('input[name="query"]');
    
    searchInput.addEventListener('input', (e) => {
      clearTimeout(this.timeout);
      
      this.timeout = setTimeout(() => {
        this.pushEvent("search", { query: e.target.value });
      }, 300); // 300ms debounce
    });
  }
};

export default SearchHook;
```

### LiveView Integration

```elixir
def handle_event("search", %{"query" => query}, socket) do
  # Debouncing is handled client-side
  socket =
    socket
    |> assign(:query, query)
    |> assign(:page, 1)
    |> perform_search()
  
  {:noreply, socket}
end
```

## Performance Optimizations

### Query Optimization

```elixir
defp optimize_search_query(query) do
  # Limit search terms to prevent performance issues
  terms = 
    query
    |> String.split()
    |> Enum.take(10) # Max 10 terms
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.replace(&1, ~r/[^\w\s-]/, ""))
  
  # Use prefix matching for better performance
  Enum.map_join(terms, " & ", &"#{&1}:*")
end
```

### Result Caching

```elixir
def search_with_cache(query, opts \\ []) do
  cache_key = "search:#{query}:#{opts[:page] || 1}"
  
  case Cachex.get(:search_cache, cache_key) do
    {:ok, nil} ->
      results = perform_search(query, opts)
      Cachex.put(:search_cache, cache_key, results, ttl: :timer.minutes(5))
      results
    
    {:ok, results} ->
      results
  end
end
```

### Pagination

```elixir
def paginate(query, %{page: page, per_page: per_page}) do
  offset = (page - 1) * per_page
  
  query
  |> limit(^per_page)
  |> offset(^offset)
end
```

## Search Analytics

### Search Tracking

```elixir
def track_search(user_id, query, results_count, search_type) do
  %SearchAnalytics{}
  |> SearchAnalytics.changeset(%{
    user_id: user_id,
    query: query,
    results_count: results_count,
    search_type: search_type,
    timestamp: DateTime.utc_now()
  })
  |> Repo.insert()
end
```

### Popular Searches

```elixir
def get_popular_searches(limit \\ 10) do
  from(s in SearchAnalytics,
    group_by: s.query,
    select: {s.query, count(s.id)},
    order_by: [desc: count(s.id)],
    limit: ^limit
  )
  |> Repo.all()
end
```

## Advanced Search Features

### Search Filters

```elixir
def search_with_filters(query, filters, opts \\ []) do
  base_query = build_base_search_query(query)
  
  base_query
  |> apply_date_filter(filters[:date_range])
  |> apply_user_filter(filters[:user_id])
  |> apply_room_filter(filters[:room_id])
  |> paginate(opts)
  |> Repo.all()
end
```

### Search Suggestions

```elixir
def get_search_suggestions(partial_query) do
  # Implement autocomplete suggestions
  # Could use previous searches, user names, etc.
  suggestions = 
    from(s in SearchAnalytics,
      where: ilike(s.query, ^"#{partial_query}%"),
      group_by: s.query,
      select: s.query,
      order_by: [desc: count(s.id)],
      limit: 5
    )
    |> Repo.all()
  
  suggestions
end
```

## Search Configuration

### Search Settings

```elixir
# config/config.exs
config :slap, :search,
  min_query_length: 2,
  max_query_length: 100,
  results_per_page: 20,
  max_search_terms: 10,
  cache_ttl: :timer.minutes(5)
```

### Search Indexing

```elixir
def update_search_index(message) do
  # Trigger search index update
  # This is handled automatically by PostgreSQL triggers
  :ok
end
```

## Error Handling

### Search Errors

```elixir
defp handle_search_error(error) do
  case error do
    %Postgrex.Error{postgres: %{code: :invalid_text_representation}} ->
      {:error, "Invalid search query"}
    
    %Postgrex.Error{postgres: %{code: :syntax_error}} ->
      {:error, "Search syntax error"}
    
    _ ->
      {:error, "Search failed"}
  end
end
```

### Empty Results

```elixir
defp handle_empty_results(query) do
  # Provide helpful suggestions for empty results
  suggestions = get_search_suggestions(String.slice(query, 0, 3))
  
  %{
    results: [],
    suggestions: suggestions,
    message: "No results found. Try different keywords or check spelling."
  }
end
```

## Testing

### Unit Tests

```elixir
defmodule Slap.ChatTest do
  use Slap.DataCase
  
  test "searches messages with valid query" do
    room = room_fixture()
    user = user_fixture()
    
    message1 = message_fixture(%{body: "Hello world"}, room, user)
    message2 = message_fixture(%{body: "Hello Elixir"}, room, user)
    
    results = Slap.Chat.search_messages(room.id, "Hello")
    
    assert length(results) == 2
    assert Enum.any?(results, &(&1.id == message1.id))
    assert Enum.any?(results, &(&1.id == message2.id))
  end
  
  test "returns empty results for non-matching query" do
    room = room_fixture()
    user = user_fixture()
    
    message_fixture(%{body: "Hello world"}, room, user)
    
    results = Slap.Chat.search_messages(room.id, "nonexistent")
    
    assert results == []
  end
end
```

### Integration Tests

```elixir
defmodule SlapWeb.MessageSearchLiveTest do
  use SlapWeb.ConnCase
  
  test "searches messages and displays results", %{conn: conn} do
    user = user_fixture()
    room = room_fixture()
    message = message_fixture(%{body: "Test message"}, room, user)
    
    {:ok, view, _html} = live(conn, "/search?room_id=#{room.id}")
    
    view
    |> form("form", query: "Test")
    |> render_submit()
    
    assert render(view) =~ "Test message"
    assert render(view) =~ "Found 1 results"
  end
end
```

## Future Enhancements

### Planned Features

- Search across message attachments
- Image search with OCR
- Voice message transcription search
- Search result filtering
- Search history
- Advanced search operators (AND, OR, NOT)
- Search result export
- Search analytics dashboard

### Technical Improvements

- Elasticsearch integration for advanced search
- Search result personalization
- Machine learning for search relevance
- Real-time search indexing
- Distributed search for scaling

This search system provides a powerful and efficient way for users to find relevant content within their conversations while maintaining good performance and user experience.