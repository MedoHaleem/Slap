defmodule SlapWeb.ChatRoomLive.SidebarComponent do
  use SlapWeb, :live_component

  alias Slap.Chat.Room
  alias Slap.Accounts.User
  alias SlapWeb.OnlineUsers
  alias Slap.DirectMessaging

  @impl true
  def update(assigns, socket) do
    # Assign all passed assigns first, excluding reserved assigns
    assigns = Map.drop(assigns, [:myself])
    socket = assign(socket, assigns)

    # Initialize unread count only if not already present and connected
    socket =
      if socket.assigns[:dm_unread_count] == nil && Phoenix.LiveView.connected?(socket) do
        # Subscribe to direct messages for real-time updates
        SlapWeb.Endpoint.subscribe("direct_messages:#{socket.assigns.current_user.id}")

        # Get unread conversation count
        dm_unread_count =
          DirectMessaging.get_unread_conversation_count(socket.assigns.current_user)

        socket
        |> assign(dm_unread_count: dm_unread_count)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col shrink-0 w-64 bg-slate-100">
      <div class="flex justify-between items-center shrink-0 h-16 border-b border-slate-300 px-4">
        <div class="flex flex-col gap-1.5">
          <h1 class="text-lg font-bold text-gray-800">
            Slap
          </h1>
        </div>
      </div>
      
      <div class="mt-4 overflow-auto">
        <div class="flex items-center h-8 px-3">
          <.toggler on_click={toggle_rooms()} dom_id="rooms-toggler" text="Rooms" />
        </div>
        
        <div id="rooms-list">
          <.room_link
            :for={{room, unread_count} <- @rooms}
            room={room}
            active={room.id == @current_room_id}
            unread_count={unread_count}
          />
          <button class="group relative flex items-center h-8 text-sm pl-8 pr-3 hover:bg-slate-300 cursor-pointer w-full">
            <.icon name="hero-plus" class="h-4 w-4 relative top-px" />
            <span class="ml-2 leading-none">Add rooms</span>
            <div class="hidden group-focus:block cursor-default absolute top-8 right-2 bg-white border-slate-200 border py-3 rounded-lg">
              <div class="w-full text-left">
                <div class="hover:bg-sky-600">
                  <div
                    phx-click={JS.navigate(~p"/rooms")}
                    class="cursor-pointer whitespace-nowrap text-gray-800 hover:text-white px-6 py-1"
                  >
                    Browse rooms
                  </div>
                  
                  <div
                    phx-click={
                      JS.navigate(~p"/rooms/#{@current_room_id}/new") |> show_modal("new-room-modal")
                    }
                    class="block select-none cursor-pointer whitespace-nowrap text-gray-800 hover:text-white px-6 py-1 block hover:bg-sky-600"
                  >
                    Create a new room
                  </div>
                </div>
              </div>
            </div>
          </button>
        </div>
        
        <div class="mt-4">
          <div class="flex items-center h-8 px-3">
            <.link
              patch={~p"/search/#{@current_room_id}"}
              class="flex items-center grow hover:bg-slate-200 px-2 py-1 rounded"
            >
              <.icon name="hero-magnifying-glass" class="h-4 w-4" />
              <span class="ml-2 leading-none font-medium text-sm">Search</span>
            </.link>
          </div>
          
          <div class="flex items-center h-8 px-3 mt-1">
            <div class="flex items-center grow">
              <.toggler on_click={toggle_users()} dom_id="users-toggler" text="Users" />
              <.unread_message_counter count={@dm_unread_count || 0} />
            </div>
          </div>
          
          <div id="users-list">
            <.user
              :for={user <- @users}
              user={user}
              online={OnlineUsers.online?(@online_users, user.id)}
              current_user={@current_user}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :dom_id, :string, required: true
  attr :text, :string, required: true
  attr :on_click, JS, required: true

  defp toggler(assigns) do
    ~H"""
    <button id={@dom_id} phx-click={@on_click} class="flex items-center grow">
      <.icon id={@dom_id <> "-chevron-down"} name="hero-chevron-down" class="h-4 w-4" />
      <.icon
        id={@dom_id <> "-chevron-right"}
        name="hero-chevron-right"
        class="h-4 w-4"
        style="display:none;"
      />
      <span class="ml-2 leading-none font-medium text-sm">
        {@text}
      </span>
    </button>
    """
  end

  defp toggle_rooms() do
    JS.toggle(to: "#rooms-toggler-chevron-down")
    |> JS.toggle(to: "#rooms-toggler-chevron-right")
    |> JS.toggle(to: "#rooms-list")
  end

  defp toggle_users() do
    JS.toggle(to: "#users-toggler-chevron-down")
    |> JS.toggle(to: "#users-toggler-chevron-right")
    |> JS.toggle(to: "#users-list")
  end

  attr :user, User, required: true
  attr :online, :boolean, default: false
  attr :current_user, User, required: true

  defp user(assigns) do
    ~H"""
    <div class="flex items-center h-8 hover:bg-gray-300 text-sm pl-8 pr-3 justify-between group">
      <.link class="flex items-center" href="#">
        <div class="flex justify-center w-4">
          <%= if @online do %>
            <span class="w-2 h-2 rounded-full bg-blue-500"></span>
          <% else %>
            <span class="w-2 h-2 rounded-full border-2 border-gray-500"></span>
          <% end %>
        </div>
         <span class="ml-2 leading-none">{@user.username}</span>
      </.link>
      
      <div class="flex items-center space-x-2">
        <%= if @online && @user.id != @current_user.id do %>
          <a
            href={~p"/voice-chat/#{@user.id}"}
            target="_blank"
            class="voice-chat-btn opacity-0 group-hover:opacity-100"
            title="Start voice chat in new window"
          >
            <.icon name="hero-microphone" class="h-4 w-4 text-gray-600 hover:text-gray-800" />
          </a>
        <% end %>
        
        <%= if @user.id != @current_user.id do %>
          <button
            phx-click="start-direct-message"
            phx-value-user-id={@user.id}
            class="opacity-0 group-hover:opacity-100"
            title="Send direct message"
          >
            <.icon
              name="hero-chat-bubble-bottom-center-text"
              class="h-4 w-4 text-gray-600 hover:text-blue-600"
            />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :room, Room, required: true
  attr :unread_count, :integer, required: true

  defp room_link(assigns) do
    ~H"""
    <.link
      class={[
        "flex items-center h-8 text-sm pl-8 pr-3",
        (@active && "bg-slate-300") || "hover:bg-slate-300"
      ]}
      patch={~p"/rooms/#{@room}"}
    >
      <.icon name="hero-hashtag" class="h-4 w-4" />
      <span class={["ml-2 leading-none", @active && "font-bold"]}>
        {@room.name}
      </span>
       <.unread_message_counter count={@unread_count} />
    </.link>
    """
  end

  attr :count, :integer, required: true

  defp unread_message_counter(assigns) do
    ~H"""
    <span
      :if={@count > 0}
      class="flex items-center justify-center bg-blue-500 rounded-full font-medium h-5 px-2 ml-auto text-xs text-white"
    >
      {@count}
    </span>
    """
  end

  def handle_info({:new_direct_message, message}, socket) do
    current_user = socket.assigns.current_user

    # Only update unread count if message wasn't sent by current user
    if message.user_id != current_user.id do
      update_unread_count(socket)
    else
      {:noreply, socket}
    end
  end

  def handle_info({:conversation_read, user_id, _timestamp}, socket) do
    current_user = socket.assigns.current_user

    if user_id != current_user.id do
      # Update unread count when other participants read messages
      update_unread_count(socket)
    else
      {:noreply, socket}
    end
  end

  def handle_info({:conversation_deleted, _conversation_id}, socket) do
    update_unread_count(socket)
  end

  defp update_unread_count(socket) do
    current_user = socket.assigns.current_user

    # Get updated unread count
    dm_unread_count = DirectMessaging.get_unread_conversation_count(current_user)

    # Send update to parent live view
    send(self(), {:update_dm_unread_count, dm_unread_count})

    {:noreply, assign(socket, dm_unread_count: dm_unread_count)}
  end
end
