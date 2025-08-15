# Implementation Plan

[Overview]
Refactor and enhance the search comment feature to improve performance, user experience, and code maintainability by unifying search implementations and adding advanced search capabilities.

The current search functionality suffers from code duplication between the dedicated search page and inline chat search, inconsistent UI styling, poor performance due to lack of debouncing, and limited search capabilities. This implementation will create a unified, performant, and user-friendly search system with advanced features like search highlighting, filtering, and pagination.

[Types]
Create a comprehensive search type system with structured data types for search queries, results, and filters.

```elixir
# Search query parameters
defmodule Slap.Chat.SearchQuery do
  @enforce_keys [:room_id, :query]
  defstruct [
    :room_id,
    :query,
    :user_id,
    :before_date,
    :after_date,
    :message_type,
    :limit,
    :offset,
    :sort_by
  ]
end

# Search result with metadata
defmodule Slap.Chat.SearchResult do
  @enforce_keys [:message, :relevance_score, :matched_fields]
  defstruct [
    :message,
    :relevance_score,
    :matched_fields,
    :highlights
  ]
end

# Search filter options
defmodule Slap.Chat.SearchFilters do
  @enforce_keys []
  defstruct [
    :users,
    :date_range,
    :message_types,
    :has_attachments,
    :has_reactions
  ]
end

# Search result metadata
defmodule Slap.Chat.SearchMetadata do
  @enforce_keys [:total_count, :page_count, :current_page]
  defstruct [
    :total_count,
    :page_count,
    :current_page,
    :query_time,
    :suggestions
  ]
end
```

[Files]
Create a unified search system with shared components and improved functionality.

- New files to be created:
  - `lib/slap/chat/search.ex` - Core search functionality module
  - `lib/slap_web/live/shared/search_component.ex` - Reusable search component
  - `lib/slap_web/live/shared/search_results_component.ex` - Search results display component
  - `lib/slap_web/live/shared/search_filters_component.ex` - Search filters component
  - `assets/js/hooks/SearchInput.js` - Debounced search input hook
  - `assets/js/hooks/SearchHighlight.js` - Search result highlighting hook
  - `test/slap_web/live/shared/search_component_test.exs` - Search component tests
  - `test/slap/chat/search_test.exs` - Search functionality tests

- Existing files to be modified:
  - `lib/slap/chat.ex` - Extract and enhance search functionality
  - `lib/slap_web/live/message_search_live.ex` - Refactor to use shared components
  - `lib/slap_web/live/chat_room_live.ex` - Update to use unified search
  - `lib/slap_web/live/chat_room_live/room_header_component.ex` - Improve search integration
  - `priv/repo/migrations/20250815115234_add_message_search_index.exs` - Enhance search index

- Files to be deleted:
  - None (existing implementations will be refactored)

[Functions]
Implement a comprehensive search function system with optimized queries and enhanced features.

- New functions:
  - `Slap.Chat.search/1` - Main search function with query building
  - `Slap.Chat.build_search_query/1` - Parse and validate search parameters
  - `Slap.Chat.perform_search/1` - Execute search with PostgreSQL full-text
  - `Slap.Chat.highlight_search_terms/2` - Add highlighting to search results
  - `Slap.Chat.get_search_suggestions/2` - Provide search suggestions
  - `Slap.Chat.save_search_history/3` - Track user search history
  - `Slap.Chat.get_search_history/2` - Retrieve user's search history
  - `Slap.Chat.clear_search_history/2` - Clear user search history

- Modified functions:
  - `Slap.Chat.search_messages/2` - Refactor to use new search system
  - `Slap.Chat.broadcast_search_results/2` - Enhance with metadata
  - `SlapWeb.MessageSearchLive.handle_event/3` - Simplify using shared components
  - `SlapWeb.ChatRoomLive.handle_event/3` - Update search handling

- Removed functions:
  - None (existing functions will be refactored)

[Classes]
Create modular components for a consistent and reusable search interface.

- New classes:
  - `SlapWeb.Shared.SearchComponent` - Reusable search input component
  - `SlapWeb.Shared.SearchResultsComponent` - Search results display component
  - `SlapWeb.Shared.SearchFiltersComponent` - Search filters component
  - `SlapWeb.Shared.SearchHistoryComponent` - Search history component

- Modified classes:
  - `SlapWeb.MessageSearchLive` - Refactor to use shared components
  - `SlapWeb.ChatRoomLive` - Update search integration
  - `SlapWeb.ChatRoomLive.RoomHeaderComponent` - Improve search UI

- Removed classes:
  - None (existing components will be refactored)

[Dependencies]
Add necessary dependencies for enhanced search functionality and improved user experience.

- New dependencies:
  - `{:highlight, "~> 0.5.0"}` - For search result highlighting
  - `{:ecto_paged_query, "~> 0.1.0"}` - For search result pagination
  - `{:timex, "~> 3.7"}` - For date filtering in search

- Modified dependencies:
  - Update existing PostgreSQL-related dependencies for better search performance

[Testing]
Implement comprehensive testing for the enhanced search functionality.

- New test files:
  - `test/slap/chat/search_test.exs` - Core search functionality tests
  - `test/slap_web/live/shared/search_component_test.exs` - Search component tests
  - `test/slap_web/live/shared/search_results_component_test.exs` - Search results tests
  - `test/support/fixtures/search_fixtures.ex` - Search-related test fixtures

- Test coverage:
  - Search query building and validation
  - Full-text search performance
  - Search result highlighting
  - Search filters and pagination
  - Component rendering and event handling
  - Integration with existing chat functionality

[Implementation Order]
Execute the refactoring in a logical sequence to ensure smooth integration and minimal disruption.

1. Create core search module with enhanced functionality
2. Implement shared search components
3. Add JavaScript hooks for improved UX
4. Refactor existing search implementations
5. Add search filters and advanced features
6. Implement search history and suggestions
7. Add comprehensive tests
8. Optimize performance and add pagination
9. Update documentation and deploy changes
