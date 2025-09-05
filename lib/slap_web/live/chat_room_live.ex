defmodule SlapWeb.ChatRoomLive do
  use SlapWeb, :live_view
  alias Phoenix.LiveView.JS

  import SlapWeb.SocketHelpers
  # Add this to access user_avatar
  import SlapWeb.UserComponents

  alias Slap.Accounts
  alias Slap.Chat
  alias Slap.Chat.{Message, Room}
  alias SlapWeb.OnlineUsers

  alias SlapWeb.ChatRoomLive.{
    ThreadComponent,
    SidebarComponent,
    RoomHeaderComponent,
    MessageListComponent,
    MessageFormComponent,
    JoinRoomComponent
  }

  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    rooms = Chat.list_joined_rooms_with_unread_counts(socket.assigns.current_user)
    timezone = get_connect_params(socket)["timezone"]
    current_user = socket.assigns.current_user

    OnlineUsers.subscribe()
    Accounts.subscribe_to_user_avatars()

    Enum.each(rooms, fn {chat, _} -> Chat.subscribe_to_room(chat) end)

    # Track user for online presence and voice calls
    dm_unread_count =
      if connected?(socket) do
        OnlineUsers.track(self(), current_user)
        # Subscribe to voice call requests
        SlapWeb.Endpoint.subscribe("voice:#{current_user.id}")
        # Initialize dm_unread_count
        Slap.DirectMessaging.get_unread_conversation_count(current_user)
      else
        0
      end

    socket
    |> assign(rooms: rooms, timezone: timezone, users: users)
    |> assign(online_users: OnlineUsers.list())
    |> assign(incoming_call: nil)
    |> assign(dm_unread_count: dm_unread_count)
    # Initialize search_query
    |> assign(search_query: nil)
    # Initialize DM state
    |> assign(show_dm: false)
    |> stream_configure(:messages,
      dom_id: fn
        %Message{id: id} -> "messages-#{id}"
        %Slap.Chat.Reply{id: id} -> "replies-#{id}"
        :unread_marker -> "messages-unread-marker"
        %Date{} = date -> to_string(date)
      end
    )
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={SidebarComponent}
      id="sidebar"
      rooms={@rooms}
      users={@users}
      online_users={@online_users}
      current_room_id={@room.id}
      current_room={@room}
      current_user={@current_user}
      dm_unread_count={@dm_unread_count}
    />
    <div class="flex flex-col grow shadow-lg">
      <.live_component
        module={RoomHeaderComponent}
        id="room-header"
        room={@room}
        hide_topic?={@hide_topic?}
        joined?={@joined?}
        current_user={@current_user}
      />
      <div class="p-2 border-b">
        <form phx-change="search" phx-submit="search">
          <div class="flex gap-2">
            <input
              type="text"
              name="query"
              value={@search_query || ""}
              placeholder="Search messages..."
              class="flex-1 px-3 py-2 border rounded-md"
            />
            <%= if @search_query do %>
              <button
                type="button"
                phx-click="clear_search"
                class="px-3 py-2 text-gray-500 hover:text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
              >
                Clear
              </button>
            <% end %>
          </div>
        </form>
      </div>
      
      <%= if @search_query do %>
        <div class="p-4 bg-gray-100 search-results-container">
          <div class="flex justify-between items-center mb-4">
            <h3 class="font-bold text-lg">Search Results</h3>
             <span class="text-sm text-gray-500">{length(@search_results)} results found</span>
          </div>
          
          <div class="space-y-3">
            <%= for message <- @search_results do %>
              <div class="p-3 bg-white rounded-lg shadow-sm border border-gray-200 hover:shadow-md transition-shadow">
                <div class="flex items-start justify-between mb-2">
                  <div class="flex items-center">
                    <.user_avatar user={message.user} class="h-8 w-8 rounded-full mr-3" />
                    <div>
                      <div class="group relative inline-flex items-center">
                        <span class="font-medium text-gray-900">{message.user.username}</span>
                        <%= if message.user.id != @current_user.id do %>
                          <button
                            phx-click="start-direct-message"
                            phx-value-user-id={message.user.id}
                            class="ml-1 hidden group-hover:inline-flex items-center justify-center w-4 h-4 text-gray-400 hover:text-blue-600 transition-all opacity-0 group-hover:opacity-100"
                            title="Send direct message"
                          >
                            <.icon name="hero-chat-bubble-bottom-center-text" class="h-3 w-3" />
                          </button>
                        <% end %>
                      </div>
                      
                      <%= if Map.get(message, :type) == :reply do %>
                        <span class="ml-2 px-2 py-1 text-xs bg-purple-100 text-purple-800 rounded-full">
                          In Thread
                        </span>
                      <% end %>
                      
                      <span class="text-gray-500 text-sm ml-2 block">
                        {Calendar.strftime(message.inserted_at, "%b %d, %Y at %H:%M")}
                      </span>
                    </div>
                  </div>
                  
                  <.link
                    patch={
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
        </div>
      <% else %>
        <.live_component
          module={MessageListComponent}
          id="message-list"
          streams={@streams}
          current_user={@current_user}
          timezone={@timezone}
        />
      <% end %>
      
      <.live_component
        :if={@joined?}
        module={MessageFormComponent}
        id="message-form"
        form={@new_message_form}
        room={@room}
        current_user={@current_user}
      /> <.live_component :if={!@joined?} module={JoinRoomComponent} id="join-room" room={@room} />
    </div>

    <%= if assigns[:profile] do %>
      <.live_component
        id="profile"
        module={SlapWeb.ChatRoomLive.ProfileComponent}
        current_user={@current_user}
        user={@profile}
      />
    <% end %>

    <%= if assigns[:thread] do %>
      <.live_component
        id="thread"
        module={ThreadComponent}
        message={@thread}
        room={@room}
        joined?={@joined?}
        timezone={@timezone}
        current_user={@current_user}
        thread_highlight_id={@thread_highlight_id}
      />
    <% end %>

    <%= if @incoming_call do %>
      <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 max-w-md w-full">
          <div class="text-center mb-4">
            <div class="w-16 h-16 bg-purple-100 rounded-full flex items-center justify-center mx-auto mb-4 animate-pulse">
              <.icon name="hero-phone" class="h-8 w-8 text-purple-600" />
            </div>
            
            <h3 class="text-lg font-bold">Incoming Call</h3>
            
            <p class="text-gray-600">{@incoming_call.username} is calling you</p>
          </div>
          
          <div class="flex space-x-3 justify-center">
            <button
              id="accept-call-button"
              phx-click="accept_call"
              phx-hook="VoiceChat"
              data-url={"/voice-chat/#{@incoming_call.user_id}?accepted_call=true"}
              data-call-id={@incoming_call.call_id}
              class="bg-green-500 hover:bg-green-600 text-white px-6 py-2 rounded-full flex items-center"
            >
              <.icon name="hero-phone" class="h-5 w-5 mr-2" /> Accept
            </button>
            
            <button
              phx-click="reject_call"
              class="bg-red-500 hover:bg-red-600 text-white px-6 py-2 rounded-full flex items-center"
            >
              <.icon name="hero-x-mark" class="h-5 w-5 mr-2" /> Reject
            </button>
          </div>
        </div>
      </div>
    <% end %>

    <.modal
      id="new-room-modal"
      show={@live_action == :new}
      on_cancel={JS.navigate(~p"/rooms/#{@room}")}
    >
      <.header>New chat room</.header>
      
      <.live_component
        module={SlapWeb.ChatRoomLive.FormComponent}
        id="new-room-form-component"
        current_user={@current_user}
      />
    </.modal>

    <div id="emoji-picker-wrapper" class="absolute" phx-update="ignore"></div>

    <%= if @show_dm do %>
      <.live_component
        id="direct-messaging"
        module={SlapWeb.DirectMessagingComponent}
        current_user={@current_user}
        target_user={@dm_target_user}
      />
    <% end %>
    """
  end

  def handle_params(params, _uri, socket) do
    room =
      case Map.fetch(params, "id") do
        {:ok, id} ->
          Chat.get_room!(id)

        :error ->
          Chat.get_first_room!()
      end

    page = Chat.list_messages_in_room(room)
    last_read_id = Chat.get_last_read_id(room, socket.assigns.current_user)

    Chat.update_last_read_id(room, socket.assigns.current_user)

    # Handle thread and highlight parameters
    {socket, thread_message_id, highlight_message_id} = handle_navigation_params(socket, params)

    socket
    |> assign(
      hide_topic?: false,
      joined?: Chat.joined?(room, socket.assigns.current_user),
      room: room,
      last_read_id: last_read_id,
      page_title: "#" <> room.name,
      thread_highlight_id: highlight_message_id,
      highlight_message_id: highlight_message_id
    )
    |> stream(:messages, [], reset: true)
    |> stream_message_page(page)
    |> assign_message_form(Chat.change_message(%Message{}))
    |> push_event("reset_pagination", %{can_load_more: !is_nil(page.metadata.after)})
    |> push_event("scroll_messages_to_bottom", %{})
    |> update(:rooms, fn rooms ->
      room_id = room.id

      Enum.map(rooms, fn
        {%Room{id: ^room_id} = room, _} -> {room, 0}
        other -> other
      end)
    end)
    |> maybe_open_thread(thread_message_id)
    |> maybe_highlight_message(highlight_message_id)
    |> noreply()
  end

  defp maybe_open_thread(socket, nil), do: socket

  defp maybe_open_thread(socket, thread_message_id) do
    case Integer.parse(thread_message_id) do
      {thread_id, _} ->
        thread_message = Chat.get_message!(thread_id)

        socket
        |> assign(:thread, thread_message)
        |> push_event("highlight_thread_message", %{
          message_id: socket.assigns.thread_highlight_id
        })

      :error ->
        socket
    end
  end

  defp maybe_highlight_message(socket, nil), do: socket

  defp maybe_highlight_message(socket, highlight_message_id) do
    case Integer.parse(highlight_message_id) do
      {message_id, _} ->
        # Only highlight if not opening a thread (thread handles its own highlighting)
        if !socket.assigns[:thread] do
          socket
          |> push_event("highlight_message", %{id: message_id})
        else
          socket
        end

      :error ->
        socket
    end
  end

  defp stream_message_page(socket, %Paginator.Page{} = page) do
    last_read_id = socket.assigns.last_read_id

    messages =
      page.entries
      |> Enum.reverse()
      |> insert_date_dividers(socket.assigns.timezone)
      |> insert_unread_marker(last_read_id)
      |> Enum.reverse()

    socket
    |> stream(:messages, messages, at: 0)
    |> assign(:message_cursor, page.metadata.after)
  end

  def handle_event("load-more-messages", _, socket) do
    page =
      Chat.list_messages_in_room(
        socket.assigns.room,
        after: socket.assigns.message_cursor
      )

    socket
    |> stream_message_page(page)
    |> reply(%{can_load_more: !is_nil(page.metadata.after)})
  end

  def handle_event("close-thread", _, socket) do
    assign(socket, :thread, nil) |> noreply()
  end

  def handle_event("show-thread", %{"id" => message_id}, socket) do
    message = Chat.get_message!(message_id)

    socket |> assign(profile: nil, thread: message) |> noreply()
  end

  def handle_event("submit-message", %{"message" => message_params}, socket) do
    %{current_user: current_user, room: room} = socket.assigns

    socket =
      if Chat.joined?(room, current_user) do
        case Chat.create_message(room, message_params, current_user) do
          {:ok, _message} ->
            assign_message_form(socket, Chat.change_message(%Message{}))

          {:error, changeset} ->
            assign_message_form(socket, changeset)
        end
      else
        socket
      end

    socket |> noreply()
  end

  def handle_event("validate-message", %{"message" => message_params}, socket) do
    changeset = Chat.change_message(%Message{}, message_params)

    assign_message_form(socket, changeset) |> noreply()
  end

  def handle_event("delete-message", %{"id" => id, "type" => "Message"}, socket) do
    Chat.delete_message_by_id(id, socket.assigns.current_user)
    socket |> noreply()
  end

  def handle_event("delete-message", %{"id" => id, "type" => "Reply"}, socket) do
    Chat.delete_reply_by_id(id, socket.assigns.current_user)

    socket |> noreply()
  end

  def handle_event("add-reaction", %{"emoji" => emoji, "message_id" => message_id}, socket) do
    message = Chat.get_message!(message_id)

    Chat.add_reaction(emoji, message, socket.assigns.current_user)

    socket |> noreply()
  end

  def handle_event("search", %{"query" => query}, socket) do
    trimmed_query = String.trim(query)

    if trimmed_query == "" do
      # Refetch the original room messages when search is cleared
      page = Chat.list_messages_in_room(socket.assigns.room)

      socket =
        socket
        |> assign(search_results: [], search_query: nil, search_count: 0)
        |> stream(:messages, [], reset: true)
        |> stream_message_page(page)
        |> push_event("reset_pagination", %{can_load_more: !is_nil(page.metadata.after)})

      socket |> noreply()
    else
      room_id = socket.assigns.room.id
      results = Chat.search_messages(room_id, trimmed_query, limit: 20, include_threads: true)
      total_count = Chat.count_search_results(room_id, trimmed_query)
      Chat.broadcast_search_results(room_id, results)

      assign(socket,
        search_results: results,
        search_query: trimmed_query,
        search_count: total_count
      )
      |> noreply()
    end
  end

  def handle_event("clear_search", _, socket) do
    # Refetch the original room messages when search is cleared
    page = Chat.list_messages_in_room(socket.assigns.room)

    socket =
      socket
      |> assign(search_results: [], search_query: nil, search_count: 0)
      |> stream(:messages, [], reset: true)
      |> stream_message_page(page)
      |> push_event("reset_pagination", %{can_load_more: !is_nil(page.metadata.after)})

    socket |> noreply()
  end

  def handle_event("remove-reaction", %{"message_id" => message, "emoji" => emoji}, socket) do
    message = Chat.get_message!(message)

    Chat.remove_reaction(emoji, message, socket.assigns.current_user)

    socket |> noreply()
  end

  def handle_event("toggle-topic", _, socket) do
    update(socket, :hide_topic?, fn hide -> !hide end) |> noreply()
  end

  def handle_event("show-profile", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)
    assign(socket, profile: user, thread: nil) |> noreply()
  end

  def handle_event("start-direct-message", %{"user-id" => user_id}, socket) do
    _current_user = socket.assigns.current_user

    try do
      # Validate that user_id is a valid integer
      target_user =
        case Integer.parse(user_id) do
          {parsed_user_id, ""} ->
            Accounts.get_user!(parsed_user_id)

          _ ->
            raise Ecto.NoResultsError, queryable: Slap.Accounts.User
        end

      # Show the DM panel which will handle conversation creation and selection
      socket
      |> assign(show_dm: true)
      |> assign(dm_target_user: target_user)
      |> noreply()
    rescue
      Ecto.NoResultsError ->
        socket
        |> put_flash(:error, "User not found")
        |> noreply()

      error ->
        # Log unexpected errors
        IO.inspect(error, label: "Unexpected error in start-direct-message")

        socket
        |> put_flash(:error, "An error occurred while starting the conversation")
        |> noreply()
    end
  end

  def handle_event("start-direct-message", _params, socket) do
    socket
    |> put_flash(:error, "Please select a user to message")
    |> noreply()
  end

  def handle_event("close-profile", _, socket) do
    assign(socket, :profile, nil) |> noreply()
  end

  def handle_event("join-room", _, socket) do
    current_user = socket.assigns.current_user
    Chat.join_room!(socket.assigns.room, current_user)
    Chat.subscribe_to_room(socket.assigns.room)

    socket =
      assign(socket,
        joined?: true,
        rooms: Chat.list_joined_rooms_with_unread_counts(current_user)
      )

    socket |> noreply()
  end

  def handle_event("accept_call", _, socket) do
    call = socket.assigns.incoming_call

    # The target_user_id for VoiceChatLive is the ID of the user who INITIATED the call (the caller).
    # The current user is accepting, so they will be the callee on that page.
    _voice_chat_url = "/voice-chat/#{call.user_id}?accepted_call=true"

    # Redirect to the voice chat page, indicating the call was just accepted.
    socket
    |> assign(incoming_call: nil)
    |> push_event("phx:open_voice_call_window", %{
      url: "/voice-chat/#{call.user_id}",
      call_id: call.call_id
    })
    |> noreply()
  end

  def handle_event("reject_call", _, socket) do
    call = socket.assigns.incoming_call
    call_topic = "voice_call:#{call.call_id}"

    # Notify caller that call was rejected
    SlapWeb.Endpoint.broadcast(call_topic, "call_rejected", %{
      by_user_id: socket.assigns.current_user.id
    })

    assign(socket, incoming_call: nil) |> noreply()
  end

  def handle_info({:new_message, message}, socket) do
    room = socket.assigns.room

    socket =
      cond do
        message.room_id == room.id ->
          Chat.update_last_read_id(room, socket.assigns.current_user)

          socket
          |> stream_insert(:messages, message)
          |> push_event("scroll_messages_to_bottom", %{})
          |> highlight_message(message)

        message.user_id != socket.assigns.current_user.id ->
          update(socket, :rooms, fn rooms ->
            Enum.map(rooms, fn
              {%Room{id: id} = room, count} when id == message.room_id -> {room, count + 1}
              other -> other
            end)
          end)

        true ->
          socket
      end

    socket |> noreply()
  end

  def handle_info({:message_deleted, message}, socket) do
    stream_delete(socket, :messages, message) |> noreply()
  end

  def handle_info({:deleted_reply, message}, socket) do
    socket
    |> refresh_message(message)
    |> noreply()
  end

  def handle_info({:new_reply, message}, socket) do
    socket =
      if socket.assigns[:thread] && socket.assigns.thread.id == message.id do
        push_event(socket, "scroll_thread_to_bottom", %{})
      else
        socket
      end

    socket
    |> refresh_message(message)
    |> noreply()
  end

  def handle_info({:added_reaction, reaction}, socket) do
    message = Chat.get_message!(reaction.message_id)

    socket
    |> refresh_message(message)
    |> noreply()
  end

  def handle_info({:removed_reaction, reaction}, socket) do
    message = Chat.get_message!(reaction.message_id)

    socket
    |> refresh_message(message)
    |> noreply()
  end

  def handle_info({:search_results, messages}, socket) do
    assign(socket, search_results: messages || []) |> noreply()
  end

  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    online_users = OnlineUsers.update(socket.assigns.online_users, diff)

    assign(socket, online_users: online_users) |> noreply()
  end

  def handle_info({:updated_avatar, user}, socket) do
    socket
    |> maybe_update_profile(user)
    |> maybe_update_current_user(user)
    |> push_event("update_avatar", %{user_id: user.id, avatar_path: user.avatar_path})
    |> noreply()
  end

  def handle_info(
        %{
          event: "voice_call_request",
          payload: %{from_user_id: user_id, from_username: username, call_id: call_id}
        },
        socket
      ) do
    # Set the incoming call information to show notification
    assign(socket,
      incoming_call: %{
        user_id: user_id,
        username: username,
        call_id: call_id
      }
    )
    |> noreply()
  end

  def handle_info({:update_dm_unread_count, dm_unread_count}, socket) do
    assign(socket, dm_unread_count: dm_unread_count) |> noreply()
  end

  def handle_info(:close_dm_panel, socket) do
    assign(socket, show_dm: false) |> noreply()
  end

  def handle_info({:direct_message_deleted, message}, socket) do
    # Forward the direct_message_deleted event to the DirectMessagingComponent
    if socket.assigns[:show_dm] do
      # Send the message directly to the DirectMessagingComponent
      send_update(SlapWeb.DirectMessagingComponent,
        id: "direct-messaging",
        direct_message_deleted: message
      )
    end

    {:noreply, socket}
  end

  # Add a catch-all handle_info to log any unhandled messages
  def handle_info(msg, socket) do
    require Logger
    Logger.debug("ChatRoomLive received unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  defp highlight_message(socket, message) do
    if message.user_id != socket.assigns.current_user.id do
      push_event(socket, "highlight_message", %{id: message.id})
    else
      socket
    end
  end

  defp maybe_update_profile(socket, user) do
    if socket.assigns[:profile] && socket.assigns.profile.id == user.id do
      assign(socket, :profile, user)
    else
      socket
    end
  end

  defp maybe_update_current_user(socket, user) do
    if socket.assigns.current_user.id == user.id do
      assign(socket, :current_user, user)
    else
      socket
    end
  end

  defp insert_date_dividers(messages, nil), do: messages

  defp insert_date_dividers(messages, timezone) do
    messages
    |> Enum.group_by(fn message ->
      message.inserted_at |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    end)
    |> Enum.sort_by(fn {date, _msg} -> date end, &(Date.compare(&1, &2) != :gt))
    |> Enum.flat_map(fn {date, messages} -> [date | messages] end)
  end

  defp insert_unread_marker(messages, nil), do: messages

  defp insert_unread_marker(messages, last_read_id) do
    {read, unread} =
      Enum.split_while(messages, fn
        %Message{} = message -> message.id <= last_read_id
        _ -> true
      end)

    if unread == [] do
      read
    else
      read ++ [:unread_marker | unread]
    end
  end

  defp assign_message_form(socket, changeset) do
    assign(socket, :new_message_form, to_form(changeset))
  end

  defp refresh_message(socket, message) do
    # Handle both Message and Reply structs
    room_id =
      case message do
        %{room_id: room_id} -> room_id
        %{message: %{room_id: room_id}} -> room_id
        _ -> nil
      end

    if room_id == socket.assigns.room.id do
      # Only stream messages, not replies (replies are handled within their parent messages)
      case message do
        %Slap.Chat.Message{} ->
          socket = stream_insert(socket, :messages, message)

          if socket.assigns[:thread] && socket.assigns.thread.id == message.id do
            assign(socket, :thread, message)
          else
            socket
          end

        %Slap.Chat.Reply{} ->
          # For replies, we need to refresh the parent message
          parent_message = Chat.get_message!(message.message_id)
          socket = stream_insert(socket, :messages, parent_message)

          if socket.assigns[:thread] && socket.assigns.thread.id == parent_message.id do
            assign(socket, :thread, parent_message)
          else
            socket
          end

        _ ->
          socket
      end
    else
      socket
    end
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

  defp handle_navigation_params(socket, params) do
    # Handle thread context from search results
    thread_message_id = Map.get(params, "thread")
    highlight_message_id = Map.get(params, "highlight")

    # Clear search results when navigating to highlight a message
    socket =
      if highlight_message_id || thread_message_id do
        assign(socket, search_results: [], search_query: nil, search_count: 0)
      else
        socket
      end

    {socket, thread_message_id, highlight_message_id}
  end
end
