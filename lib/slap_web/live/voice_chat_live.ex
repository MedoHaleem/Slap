defmodule SlapWeb.VoiceChatLive do
  use SlapWeb, :live_view
  alias Phoenix.PubSub

  def mount(%{"target_user_id" => target_user_id}, _session, socket) do
    current_user_id = socket.assigns.current_user.id

    if connected?(socket) do
      topic = "voice:#{current_user_id}"
      SlapWeb.Endpoint.subscribe(topic)

      # Create a unique channel for this call
      call_id =
        "#{min(current_user_id, String.to_integer(target_user_id))}_#{max(current_user_id, String.to_integer(target_user_id))}"

      call_topic = "voice_call:#{call_id}"
      SlapWeb.Endpoint.subscribe(call_topic)
    end

    {:ok,
     assign(socket,
       target_user_id: target_user_id,
       call_status: "init",
       call_role: nil,
       target_user: get_target_user(target_user_id),
       call_id:
         "#{min(current_user_id, String.to_integer(target_user_id))}_#{max(current_user_id, String.to_integer(target_user_id))}"
     )}
  end

  defp get_target_user(user_id) do
    Slap.Accounts.get_user!(user_id)
  end

  def handle_event("request_call", _, socket) do
    target_user_id = socket.assigns.target_user_id
    current_user = socket.assigns.current_user
    call_topic = "voice_call:#{socket.assigns.call_id}"

    # Send call request to target user
    SlapWeb.Endpoint.broadcast("voice:#{target_user_id}", "voice_call_request", %{
      from_user_id: current_user.id,
      from_username: current_user.username,
      call_id: socket.assigns.call_id
    })

    {:noreply, assign(socket, call_status: "requesting", call_role: "caller")}
  end

  def handle_event("accept_call", _, socket) do
    call_topic = "voice_call:#{socket.assigns.call_id}"

    # Notify caller that call was accepted
    SlapWeb.Endpoint.broadcast(call_topic, "call_accepted", %{
      by_user_id: socket.assigns.current_user.id
    })

    # Now initiate the WebRTC connection
    {:noreply,
     socket
     |> assign(call_status: "connecting", call_role: "callee")
     |> push_event("voice:initialize", %{initiator: false})}
  end

  def handle_event("reject_call", _, socket) do
    call_topic = "voice_call:#{socket.assigns.call_id}"

    # Notify caller that call was rejected
    SlapWeb.Endpoint.broadcast(call_topic, "call_rejected", %{
      by_user_id: socket.assigns.current_user.id
    })

    # Push a JavaScript command to close the window
    {:noreply, push_event(socket, "close_window", %{})}
  end

  def handle_event("signal", %{"data" => signal_data}, socket) do
    call_topic = "voice_call:#{socket.assigns.call_id}"

    SlapWeb.Endpoint.broadcast(call_topic, "voice_signal", %{
      signal: signal_data,
      from: socket.assigns.current_user.id
    })

    {:noreply, socket}
  end

  def handle_event("update_status", %{"status" => status}, socket) do
    {:noreply, assign(socket, call_status: status)}
  end

  def handle_event("end_call", _, socket) do
    call_topic = "voice_call:#{socket.assigns.call_id}"

    # Notify other participant the call ended
    SlapWeb.Endpoint.broadcast(call_topic, "call_ended", %{
      by_user_id: socket.assigns.current_user.id
    })

    # Push a JavaScript command to close the window
    {:noreply, push_event(socket, "close_window", %{})}
  end

  # Handle incoming signal from the other peer
  def handle_info(%{event: "voice_signal", payload: payload}, socket) do
    {:noreply, push_event(socket, "voice:receive_signal", payload)}
  end

  # Handle incoming call request
  def handle_info(
        %{
          event: "voice_call_request",
          payload: %{from_user_id: user_id, from_username: username, call_id: call_id}
        },
        socket
      ) do
    {:noreply,
     assign(socket,
       call_status: "incoming",
       call_role: "callee",
       caller: %{id: user_id, username: username}
     )}
  end

  # Handle call accepted event
  def handle_info(%{event: "call_accepted"}, socket) do
    if socket.assigns.call_role == "caller" do
      # Caller should initiate the WebRTC connection
      {:noreply,
       socket
       |> assign(call_status: "connecting")
       |> push_event("voice:initialize", %{initiator: true})}
    else
      {:noreply, socket}
    end
  end

  # Handle call rejected event
  def handle_info(%{event: "call_rejected"}, socket) do
    {:noreply, assign(socket, call_status: "rejected")}
  end

  # Handle call ended event
  def handle_info(%{event: "call_ended"}, socket) do
    {:noreply, assign(socket, call_status: "ended")}
  end

  # Status message helpers
  defp status_message("init"), do: "Click to start call"
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

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 flex flex-col">
      <div class="bg-white shadow-sm border-b border-gray-200 py-4">
        <div class="container mx-auto px-4 flex justify-between items-center">
          <div class="flex items-center">
            <h1 class="text-xl font-bold text-gray-800">Voice Chat</h1>
            <div class="ml-3 text-sm text-gray-600">
              <%= if @call_status == "incoming" do %>
                from {@caller.username}
              <% else %>
                with {@target_user.username}
              <% end %>
            </div>
          </div>

          <div class="flex items-center gap-4">
            <%= if @call_status in ["connected", "connecting"] do %>
              <button
                phx-click="end_call"
                class="bg-red-500 text-white px-4 py-2 rounded hover:bg-red-600 flex items-center"
              >
                <.icon name="hero-phone-x-mark" class="h-5 w-5 mr-2" /> End Call
              </button>
            <% end %>
            <button
              onclick="window.close()"
              class="bg-gray-200 text-gray-800 px-4 py-2 rounded hover:bg-gray-300"
            >
              Close Window
            </button>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-8 flex-1 flex flex-col items-center justify-center">
        <div class="bg-white rounded-lg shadow-md p-8 max-w-md w-full">
          <div class="text-center">
            <div class={"call-status-badge mb-6 #{status_color(@call_status)}"}>
              {status_message(@call_status)}
            </div>

            <div class="mb-8">
              <div class={"w-32 h-32 rounded-full flex items-center justify-center mx-auto #{status_bg_color(@call_status)}"}>
                <.icon name="hero-microphone" class="h-16 w-16 text-gray-500" />
              </div>

              <%= if @call_status == "connected" do %>
                <div class="audio-wave mt-4">
                  <span></span>
                  <span></span>
                  <span></span>
                  <span></span>
                  <span></span>
                </div>
              <% end %>
            </div>

            <div
              id="voice-chat-container"
              phx-hook="VoiceChat"
              data-user-id={@current_user.id}
              data-target-id={@target_user_id}
              data-call-id={@call_id}
              data-call-status={@call_status}
              class="flex flex-col items-center justify-center"
            >
              <div class="mt-4 text-center">
                <%= cond do %>
                  <% @call_status == "init" -> %>
                    <button
                      phx-click="request_call"
                      class="bg-blue-500 hover:bg-blue-600 text-white px-8 py-3 rounded-full text-lg"
                    >
                      Start Call
                    </button>
                  <% @call_status == "incoming" -> %>
                    <div class="flex space-x-4">
                      <button
                        phx-click="accept_call"
                        class="bg-green-500 hover:bg-green-600 text-white px-8 py-3 rounded-full text-lg flex items-center"
                      >
                        <.icon name="hero-phone" class="h-5 w-5 mr-2" /> Accept
                      </button>
                      <button
                        phx-click="reject_call"
                        class="bg-red-500 hover:bg-red-600 text-white px-8 py-3 rounded-full text-lg flex items-center"
                      >
                        <.icon name="hero-x-mark" class="h-5 w-5 mr-2" /> Reject
                      </button>
                    </div>
                  <% @call_status == "rejected" -> %>
                    <button
                      phx-click="end_call"
                      class="bg-gray-500 hover:bg-gray-600 text-white px-8 py-3 rounded-full text-lg"
                    >
                      Close
                    </button>
                  <% @call_status == "ended" -> %>
                    <button
                      phx-click="end_call"
                      class="bg-gray-500 hover:bg-gray-600 text-white px-8 py-3 rounded-full text-lg"
                    >
                      Close
                    </button>
                  <% String.starts_with?(@call_status, "error:") -> %>
                    <div class="mb-4 text-red-600 text-sm">
                      {String.replace_prefix(@call_status, "error: ", "")}
                    </div>
                    <button
                      phx-click="request_call"
                      class="bg-blue-500 hover:bg-blue-600 text-white px-8 py-3 rounded-full text-lg"
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
    </div>
    """
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
