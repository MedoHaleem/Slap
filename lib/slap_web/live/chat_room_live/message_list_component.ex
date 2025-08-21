defmodule SlapWeb.ChatRoomLive.MessageListComponent do
  use SlapWeb, :live_component

  alias Slap.Chat.Message
  import SlapWeb.ChatComponents

  def render(assigns) do
    ~H"""
    <div
      id="room-messages"
      phx-hook="RoomMessages"
      class="flex flex-col grow overflow-auto"
      phx-update="stream"
    >
      <%= for {dom_id, message} <- @streams.messages do %>
        <%= case message do %>
          <% :unread_marker -> %>
            <div id={dom_id} class="w-full flex text-red-500 items-center gap-3 pr-5">
              <div class="w-full h-px grow bg-red-500"></div>
              
              <div class="text-sm">New</div>
            </div>
          <% %Message{} -> %>
            <.message
              current_user={@current_user}
              dom_id={dom_id}
              message={message}
              timezone={@timezone}
            />
          <% %Date{} -> %>
            <div id={dom_id} class="flex flex-col items-center mt-2">
              <hr class="w-full" />
              <span class="flex items-center justify-center -mt-3 bg-white h-6 px-3 rounded-full border text-xs font-semibold mx-auto">
                {format_date(message)}
              </span>
            </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp format_date(%Date{} = date) do
    today = Date.utc_today()

    case Date.diff(today, date) do
      0 ->
        "Today"

      1 ->
        "Yesterday"

      _ ->
        format_str = "%A, %B %e#{ordinal(date.day)}#{if today.year != date.year, do: " %Y"}"
        Timex.format!(date, format_str, :strftime)
    end
  end

  defp ordinal(day) do
    cond do
      rem(day, 10) == 1 and day != 11 -> "st"
      rem(day, 10) == 2 and day != 12 -> "nd"
      rem(day, 10) == 3 and day != 13 -> "rd"
      true -> "th"
    end
  end
end
