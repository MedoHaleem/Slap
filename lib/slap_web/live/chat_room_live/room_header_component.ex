defmodule SlapWeb.ChatRoomLive.RoomHeaderComponent do
  use SlapWeb, :live_component

  import SlapWeb.UserComponents

  def render(assigns) do
    ~H"""
    <div class="flex justify-between items-center shrink-0 h-16 bg-white border-b border-slate-300 px-4">
      <div class="flex flex-col gap-1.5">
        <h1 class="text-sm font-bold leading-none">
          {@room.name}
          <.link
            :if={@joined?}
            class="font-normal text-xs text-blue-600 hover:text-blue-700"
            navigate={~p"/rooms/#{@room}/edit"}
          >
            Edit
          </.link>
        </h1>

        <div
          class={["text-xs leading-none h-3.5", @hide_topic? && "text-slate-600"]}
          phx-click="toggle-topic"
        >
          <%= if @hide_topic? do %>
            [Topic hidden]
          <% else %>
            {@room.topic}
          <% end %>
        </div>
      </div>

      <div class="flex-1 mx-4 max-w-md">
        <!-- Search functionality moved to dedicated page -->
      </div>

      <ul class="relative z-10 flex items-center gap-4 px-4 sm:px-6 lg:px-8 justify-end">
        <li>
          <.link
            href={~p"/search/#{@room.id}"}
            class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
          >
            Search Messages
          </.link>
        </li>

        <li class="text-[0.8125rem] leading-6 text-zinc-900">
          <div class="text-sm leading-10">
            <.link
              class="flex gap-4 items-center"
              phx-click="show-profile"
              phx-value-user-id={@current_user.id}
            >
              <.user_avatar user={@current_user} class="h-8 w-8 rounded" />
              <span class="hover:underline">{@current_user.username}</span>
            </.link>
          </div>
        </li>

        <li>
          <.link
            href={~p"/users/settings"}
            class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
          >
            Settings
          </.link>
        </li>

        <li>
          <.link
            href={~p"/users/log_out"}
            method="delete"
            class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
          >
            Log out
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
