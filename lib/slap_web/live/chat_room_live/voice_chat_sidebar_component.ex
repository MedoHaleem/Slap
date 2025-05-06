defmodule SlapWeb.ChatRoomLive.VoiceChatSidebarComponent do
  use SlapWeb, :live_component

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(collapsed: false)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col shrink-0 w-80 bg-white border-l border-slate-200 shadow-md">
      <div class="flex justify-between items-center shrink-0 h-16 border-b border-slate-200 px-4">
        <div class="flex items-center">
          <h2 class="text-lg font-bold text-gray-800">Voice Call</h2>
          <div class="ml-2 text-sm text-gray-600">
            <%= if @call_status == "incoming" do %>
              from {@caller.username}
            <% else %>
              with {@target_user.username}
            <% end %>
          </div>
        </div>
        <button
          phx-click="toggle_voice_sidebar"
          phx-target={@myself}
          class="text-gray-500 hover:text-gray-700"
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </button>
      </div>

      <div class="p-6 flex-1 flex flex-col">
        <div class={"call-status-badge my-4 #{status_color(@call_status)}"}>
          {status_message(@call_status)}
        </div>

        <div class="flex-1 flex flex-col items-center justify-center space-y-6">
          <div class={"w-24 h-24 rounded-full flex items-center justify-center #{status_bg_color(@call_status)}"}>
            <.icon name="hero-microphone" class="h-10 w-10 text-gray-500" />
          </div>

          <%= if @call_status == "connected" do %>
            <div class="audio-wave mt-2">
              <span></span>
              <span></span>
              <span></span>
              <span></span>
              <span></span>
            </div>
          <% end %>

          <div
            id="voice-chat-container"
            phx-hook="VoiceChat"
            data-user-id={@current_user.id}
            data-target-id={@target_user_id}
            data-call-id={@call_id}
            data-call-status={@call_status}
            class="w-full"
          >
            <div class="text-center">
              <%= cond do %>
                <% @call_status == "init" -> %>
                  <button
                    phx-click="request_call"
                    phx-target={@myself}
                    class="bg-blue-500 hover:bg-blue-600 text-white px-6 py-2 rounded-full"
                  >
                    Start Call
                  </button>
                <% @call_status == "incoming" -> %>
                  <div class="flex flex-col space-y-2">
                    <button
                      phx-click="accept_call"
                      phx-target={@myself}
                      class="bg-green-500 hover:bg-green-600 text-white px-6 py-2 rounded-full flex items-center justify-center"
                    >
                      <.icon name="hero-phone" class="h-4 w-4 mr-2" /> Accept
                    </button>
                    <button
                      phx-click="reject_call"
                      phx-target={@myself}
                      class="bg-red-500 hover:bg-red-600 text-white px-6 py-2 rounded-full flex items-center justify-center"
                    >
                      <.icon name="hero-x-mark" class="h-4 w-4 mr-2" /> Reject
                    </button>
                  </div>
                <% @call_status in ["connected", "connecting"] -> %>
                  <button
                    phx-click="end_call"
                    phx-target={@myself}
                    class="bg-red-500 hover:bg-red-600 text-white px-6 py-2 rounded-full"
                  >
                    End Call
                  </button>
                <% @call_status == "rejected" || @call_status == "ended" -> %>
                  <button
                    phx-click="close_voice_sidebar"
                    phx-target={@myself}
                    class="bg-gray-500 hover:bg-gray-600 text-white px-6 py-2 rounded-full"
                  >
                    Close
                  </button>
                <% String.starts_with?(@call_status, "error:") -> %>
                  <div class="mb-2 text-red-600 text-sm">
                    {String.replace_prefix(@call_status, "error: ", "")}
                  </div>
                  <button
                    phx-click="request_call"
                    phx-target={@myself}
                    class="bg-blue-500 hover:bg-blue-600 text-white px-6 py-2 rounded-full"
                  >
                    Try Again
                  </button>
                <% true -> %>
                  <!-- No buttons for other states -->
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers that forward to the parent LiveView
  def handle_event("toggle_voice_sidebar", _, socket) do
    send(self(), {:toggle_voice_sidebar})
    {:noreply, socket}
  end

  def handle_event("close_voice_sidebar", _, socket) do
    send(self(), {:close_voice_sidebar})
    {:noreply, socket}
  end

  def handle_event("request_call", _, socket) do
    send(self(), {:voice_chat_event, "request_call"})
    {:noreply, socket}
  end

  def handle_event("accept_call", _, socket) do
    send(self(), {:voice_chat_event, "accept_call"})
    {:noreply, socket}
  end

  def handle_event("reject_call", _, socket) do
    send(self(), {:voice_chat_event, "reject_call"})
    {:noreply, socket}
  end

  def handle_event("end_call", _, socket) do
    send(self(), {:voice_chat_event, "end_call"})
    {:noreply, socket}
  end

  # Status message helpers
  defp status_message("init"), do: "Ready to call"
  defp status_message("requesting"), do: "Calling..."
  defp status_message("incoming"), do: "Incoming call..."
  defp status_message("connecting"), do: "Connecting..."
  defp status_message("connected"), do: "Call connected"
  defp status_message("ended"), do: "Call ended"
  defp status_message("rejected"), do: "Call rejected"
  defp status_message("disconnected"), do: "Call disconnected"

  defp status_message(status) when is_binary(status) do
    if String.starts_with?(status, "error:") do
      "Error: #{String.replace_prefix(status, "error: ", "")}"
    else
      status
    end
  end

  # Status color helpers
  defp status_color("init"), do: "bg-blue-100 text-blue-800"
  defp status_color("requesting"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("incoming"), do: "bg-purple-100 text-purple-800"
  defp status_color("connecting"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("connected"), do: "bg-green-100 text-green-800"
  defp status_color("ended"), do: "bg-gray-100 text-gray-800"
  defp status_color("rejected"), do: "bg-red-100 text-red-800"
  defp status_color("disconnected"), do: "bg-gray-100 text-gray-800"

  defp status_color(status) when is_binary(status) do
    if String.starts_with?(status, "error:") do
      "bg-red-100 text-red-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  # Background animation colors for call status
  defp status_bg_color("init"), do: "bg-gray-200"
  defp status_bg_color("requesting"), do: "bg-yellow-200 animate-pulse"
  defp status_bg_color("incoming"), do: "bg-purple-200 animate-pulse"
  defp status_bg_color("connecting"), do: "bg-yellow-200 animate-pulse"
  defp status_bg_color("connected"), do: "bg-green-200"
  defp status_bg_color("ended"), do: "bg-gray-200"
  defp status_bg_color("rejected"), do: "bg-red-200"
  defp status_bg_color("disconnected"), do: "bg-gray-200"
  defp status_bg_color(_), do: "bg-gray-200"
end
