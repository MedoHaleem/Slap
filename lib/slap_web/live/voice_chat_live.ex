defmodule SlapWeb.VoiceChatLive do
  use SlapWeb, :live_view
    require Logger

  def mount(%{"target_user_id" => target_user_id_param} = params, _session, socket) do
    current_user_id = socket.assigns.current_user.id

    # target_user_id_param is from the path, ensure it's an integer for call_id calculation if current_user_id is int
    # Assuming current_user.id is an integer. If it can be a string, adjust accordingly.
    target_user_id_for_calc = String.to_integer(target_user_id_param)

    accepted_call = params["accepted_call"] == "true"

    # Create a unique channel for this call, consistently for both users
    call_id =
      "#{min(current_user_id, target_user_id_for_calc)}_#{max(current_user_id, target_user_id_for_calc)}"

    if connected?(socket) do
      SlapWeb.Endpoint.subscribe(topic_user(current_user_id))
      SlapWeb.Endpoint.subscribe(topic_call(call_id))
    end

    socket_with_basics =
      assign(socket,
        # Keep original param for get_target_user if it expects string
        target_user_id: target_user_id_param,
        call_id: call_id,
        # Uses the string ID from param
        target_user: get_target_user(target_user_id_param)
      )

    if accepted_call do
      # This user is the callee and has just accepted the call via ChatRoomLive.
      # They are now landing on the VoiceChatLive page. Auto-initiate the call.

      call_topic_for_broadcast = topic_call(call_id)

      SlapWeb.Endpoint.broadcast(call_topic_for_broadcast, "call_accepted", %{
        # The current user (callee) accepted
        by_user_id: current_user_id
      })

      {:ok,
       socket_with_basics
       |> assign(call_status: "connecting", call_role: "callee")
       |> push_event("voice:initialize", %{initiator: false})}
    else
      # Standard init flow (user navigated here directly, or is initiating a new call from this page)
      {:ok,
       assign(socket_with_basics,
         call_status: "init",
         call_role: nil
       )}
    end
  end


  defp get_target_user(user_id) do
    # Accept both string and integer IDs
    id =
      case user_id do
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
      end

    Slap.Accounts.get_user!(id)
  end


  def handle_event("request_call", _, socket) do
    target_user_id = socket.assigns.target_user_id
    current_user = socket.assigns.current_user

    # Send call request to target user
    SlapWeb.Endpoint.broadcast(topic_user(target_user_id), "voice_call_request", %{
      from_user_id: current_user.id,
      from_username: current_user.username,
      call_id: socket.assigns.call_id
    })

    {:noreply, assign(socket, call_status: "requesting", call_role: "caller")}
  end

  def handle_event("accept_call", _, socket) do

    # Notify caller that call was accepted
    SlapWeb.Endpoint.broadcast(topic_call(socket.assigns.call_id), "call_accepted", %{
      by_user_id: socket.assigns.current_user.id
    })

    # Now initiate the WebRTC connection
    {:noreply,
     socket
     |> assign(call_status: "connecting", call_role: "callee")
     |> push_event("voice:initialize", %{initiator: false})}
  end

  def handle_event("reject_call", _, socket) do

    # Notify caller that call was rejected
    SlapWeb.Endpoint.broadcast(topic_call(socket.assigns.call_id), "call_rejected", %{
      by_user_id: socket.assigns.current_user.id
    })

    # Push a JavaScript command to close the window
    {:noreply, push_event(socket, "close_window", %{})}
  end

  def handle_event("signal", %{"signal" => signal_data}, socket) do

    call_topic = topic_call(socket.assigns.call_id)

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
    # Notify other participant the call ended
    call_topic = topic_call(socket.assigns.call_id)
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
    <div class="relative min-h-screen bg-gray-100 flex flex-col w-full">
      <div class="absolute top-0 left-0 right-0 bg-white shadow-sm border-b border-gray-200 py-4 z-10">
        <div class="max-w-md mx-auto px-4 flex justify-between items-center">
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

      <div class="w-full flex items-center justify-center min-h-screen pt-20">
        <div class="bg-white rounded-lg shadow-md p-8 max-w-md w-full mx-auto">
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
                    <div class="flex flex-col space-y-4">
                      <button
                        phx-click="end_call"
                        class="bg-gray-500 hover:bg-gray-600 text-white px-8 py-3 rounded-full text-lg"
                      >
                        Close
                      </button>
                    </div>
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

  # Helper topic generators
  defp topic_user(user_id), do: "voice:#{user_id}"
  defp topic_call(call_id), do: "voice_call:#{call_id}"
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
def terminate(_reason, socket) do
  # Unsubscribe from user and call topics
  if socket.assigns.current_user do
    SlapWeb.Endpoint.unsubscribe("voice:#{socket.assigns.current_user.id}")
  end
  if socket.assigns.call_id do
    SlapWeb.Endpoint.unsubscribe("voice_call:#{socket.assigns.call_id}")
  end
  :ok
end

end
