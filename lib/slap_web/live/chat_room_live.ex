defmodule SlapWeb.ChatRoomLive do
  use SlapWeb, :live_view
  alias Phoenix.LiveView.JS

  import SlapWeb.SocketHelpers

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

    if connected?(socket) do
      OnlineUsers.track(self(), socket.assigns.current_user)
      # Subscribe to voice call requests
      SlapWeb.Endpoint.subscribe("voice:#{socket.assigns.current_user.id}")
    end

    OnlineUsers.subscribe()
    Accounts.subscribe_to_user_avatars()

    Enum.each(rooms, fn {chat, _} -> Chat.subscribe_to_room(chat) end)

    socket
    |> assign(rooms: rooms, timezone: timezone, users: users)
    |> assign(online_users: OnlineUsers.list())
    |> assign(incoming_call: nil)
    |> stream_configure(:messages,
      dom_id: fn
        %Message{id: id} -> "messages-#{id}"
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
      <.live_component
        module={MessageListComponent}
        id="message-list"
        streams={@streams}
        current_user={@current_user}
        timezone={@timezone}
      />
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
              phx-click="accept_call"
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

    socket
    |> assign(
      hide_topic?: false,
      joined?: Chat.joined?(room, socket.assigns.current_user),
      room: room,
      last_read_id: last_read_id,
      page_title: "#" <> room.name
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
    |> noreply()
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
    {:noreply, assign(socket, :thread, nil)}
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

    {:noreply, socket}
  end

  def handle_event("validate-message", %{"message" => message_params}, socket) do
    changeset = Chat.change_message(%Message{}, message_params)

    {:noreply, assign_message_form(socket, changeset)}
  end

  def handle_event("delete-message", %{"id" => id, "type" => "Message"}, socket) do
    Chat.delete_message_by_id(id, socket.assigns.current_user)
    {:noreply, socket}
  end

  def handle_event("delete-message", %{"id" => id, "type" => "Reply"}, socket) do
    Chat.delete_reply_by_id(id, socket.assigns.current_user)

    {:noreply, socket}
  end

  def handle_event("add-reaction", %{"emoji" => emoji, "message_id" => message_id}, socket) do
    message = Chat.get_message!(message_id)

    Chat.add_reaction(emoji, message, socket.assigns.current_user)

    {:noreply, socket}
  end

  def handle_event("remove-reaction", %{"message_id" => message, "emoji" => emoji}, socket) do
    message = Chat.get_message!(message)

    Chat.remove_reaction(emoji, message, socket.assigns.current_user)

    {:noreply, socket}
  end

  def handle_event("toggle-topic", _, socket) do
    {:noreply, update(socket, :show_topic, fn show -> !show end)}
  end

  def handle_event("show-profile", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)
    {:noreply, assign(socket, profile: user, thread: nil)}
  end

  def handle_event("close-profile", _, socket) do
    {:noreply, assign(socket, :profile, nil)}
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

    {:noreply, socket}
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

    {:noreply, socket}
  end

  def handle_info({:message_deleted, message}, socket) do
    {:noreply, stream_delete(socket, :messages, message)}
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

  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    online_users = OnlineUsers.update(socket.assigns.online_users, diff)

    {:noreply, assign(socket, online_users: online_users)}
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
    {:noreply,
     assign(socket,
       incoming_call: %{
         user_id: user_id,
         username: username,
         call_id: call_id
       }
     )}
  end

  def handle_event("accept_call", _, socket) do
    call = socket.assigns.incoming_call
    # Open voice chat in new window with the caller
    {:noreply,
     socket
     |> assign(incoming_call: nil)
     |> push_event("open_voice_chat", %{
       target_user_id: call.user_id,
       call_id: call.call_id
     })}
  end

  def handle_event("reject_call", _, socket) do
    call = socket.assigns.incoming_call
    call_topic = "voice_call:#{call.call_id}"

    # Notify caller that call was rejected
    SlapWeb.Endpoint.broadcast(call_topic, "call_rejected", %{
      by_user_id: socket.assigns.current_user.id
    })

    {:noreply, assign(socket, incoming_call: nil)}
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
    if message.room_id == socket.assigns.room.id do
      socket = stream_insert(socket, :messages, message)

      if socket.assigns[:thread] && socket.assigns.thread.id == message.id do
        assign(socket, :thread, message)
      else
        socket
      end
    else
      socket
    end
  end
end
