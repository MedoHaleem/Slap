defmodule SlapWeb.VoiceChatLive do
  @moduledoc """
  Voice chat functionality for user-to-user calls.

  Handles call initiation, signaling, and WebRTC connection management.
  """

  use SlapWeb, :live_view
  require Logger

  # ==========================
  # Module Attributes
  # ==========================

  @status_messages %{
    "init" => "Click to start call",
    "requesting" => "Calling...",
    "incoming" => "Incoming call...",
    "connecting" => "Connecting...",
    "connected" => "Call connected",
    "ended" => "Call ended",
    "rejected" => "Call rejected",
    "disconnected" => "Call disconnected"
  }

  @status_colors %{
    "init" => "bg-blue-100 text-blue-800",
    "requesting" => "bg-yellow-100 text-yellow-800",
    "incoming" => "bg-purple-100 text-purple-800",
    "connecting" => "bg-yellow-100 text-yellow-800",
    "connected" => "bg-green-100 text-green-800",
    "ended" => "bg-gray-100 text-gray-800",
    "rejected" => "bg-red-100 text-red-800",
    "disconnected" => "bg-gray-100 text-gray-800"
  }

  @status_bg_colors %{
    "init" => "bg-gray-200",
    "requesting" => "bg-yellow-200 animate-pulse",
    "incoming" => "bg-purple-200 animate-pulse",
    "connecting" => "bg-yellow-200 animate-pulse",
    "connected" => "bg-green-200",
    "ended" => "bg-gray-200",
    "rejected" => "bg-red-200",
    "disconnected" => "bg-gray-200"
  }

  # ==========================
  # Lifecycle Callbacks
  # ==========================

  @doc """
  Mounts the voice chat LiveView with proper error handling.
  """
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"target_user_id" => target_user_id_param} = params, _session, socket) do
    current_user_id = socket.assigns.current_user.id

    Logger.info(
      "VoiceChatLive mounting: current_user=#{current_user_id}, target_user=#{target_user_id_param}"
    )

    case get_target_user(target_user_id_param) do
      {:ok, target_user} ->
        target_user_id = target_user.id
        call_id = generate_call_id(current_user_id, target_user_id)

        setup_subscriptions(socket, current_user_id, call_id)

        socket =
          assign(socket,
            target_user_id: target_user_id_param,
            call_id: call_id,
            target_user: target_user
          )

        if params["accepted_call"] == "true" do
          handle_accepted_call_mount(socket, current_user_id, call_id)
        else
          {:ok, assign(socket, call_status: "init", call_role: nil)}
        end

      {:error, reason} ->
        Logger.error(
          "VoiceChatLive mount failed: target_user=#{target_user_id_param}, reason=#{inspect(reason)}"
        )

        {:ok,
         assign(socket,
           call_status: "error: User not found",
           call_role: nil,
           target_user: nil
         )}
    end
  end

  @doc """
  Cleanup on LiveView termination.
  """
  @spec terminate(term(), Phoenix.LiveView.Socket.t()) :: :ok
  def terminate(_reason, socket) do
    Logger.debug(
      "VoiceChatLive terminating: current_user=#{get_in(socket.assigns, [:current_user, :id])}"
    )

    # Unsubscribe from user and call topics
    if socket.assigns.current_user do
      SlapWeb.Endpoint.unsubscribe("voice:#{socket.assigns.current_user.id}")
    end

    if socket.assigns.call_id do
      SlapWeb.Endpoint.unsubscribe("voice_call:#{socket.assigns.call_id}")
    end

    :ok
  end

  # ==========================
  # Event Handlers
  # ==========================

  @doc """
  Handles request to start a new voice call.
  """
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("request_call", _, socket) do
    Logger.info(
      "Voice call requested: from_user=#{socket.assigns.current_user.id}, to_user=#{socket.assigns.target_user_id}"
    )

    broadcast_call_request(
      socket.assigns.target_user_id,
      socket.assigns.current_user,
      socket.assigns.call_id
    )

    {:noreply, assign(socket, call_status: "requesting", call_role: "caller")}
  end

  def handle_event("accept_call", _, socket) do
    Logger.info(
      "Voice call accepted: user=#{socket.assigns.current_user.id}, call_id=#{socket.assigns.call_id}"
    )

    broadcast_call_accepted(socket.assigns.call_id, socket.assigns.current_user.id)
    initiate_webrtc_connection(socket, false)
  end

  def handle_event("reject_call", _, socket) do
    Logger.info(
      "Voice call rejected: user=#{socket.assigns.current_user.id}, call_id=#{socket.assigns.call_id}"
    )

    broadcast_call_rejected(socket.assigns.call_id, socket.assigns.current_user.id)
    close_window(socket)
  end

  def handle_event("signal", %{"signal" => signal_data}, socket) do
    Logger.debug(
      "Voice signal received: from_user=#{socket.assigns.current_user.id}, type=#{Map.get(signal_data, "type", "unknown")}"
    )

    broadcast_voice_signal(socket.assigns.call_id, signal_data, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("update_status", %{"status" => status}, socket) do
    Logger.debug(
      "Voice call status updated: user=#{socket.assigns.current_user.id}, status=#{status}"
    )

    {:noreply, assign(socket, call_status: status)}
  end

  def handle_event("end_call", _, socket) do
    Logger.info(
      "Voice call ended: user=#{socket.assigns.current_user.id}, call_id=#{socket.assigns.call_id}"
    )

    broadcast_call_ended(socket.assigns.call_id, socket.assigns.current_user.id)
    close_window(socket)
  end

  # ==========================
  # Message Handlers
  # ==========================

  # Handle incoming signal from the other peer
  def handle_info(%{event: "voice_signal", payload: payload}, socket) do
    Logger.debug("Voice signal received from peer: from=#{payload.from}")
    {:noreply, push_event(socket, "voice:receive_signal", payload)}
  end

  # Handle incoming call request
  def handle_info(%{event: "voice_call_request", payload: payload}, socket) do
    Logger.info(
      "Incoming voice call: from=#{payload.from_user_id}, to=#{socket.assigns.current_user.id}"
    )

    {:noreply,
     assign(socket,
       call_status: "incoming",
       call_role: "callee",
       caller: %{id: payload.from_user_id, username: payload.from_username}
     )}
  end

  # Handle call accepted event
  def handle_info(%{event: "call_accepted"}, socket) do
    Logger.info(
      "Voice call accepted: by_user=#{socket.assigns.current_user.id}, role=#{socket.assigns.call_role}"
    )

    if socket.assigns.call_role == "caller" do
      initiate_webrtc_connection(socket, true)
    else
      {:noreply, socket}
    end
  end

  # Handle call rejected event
  def handle_info(%{event: "call_rejected"}, socket) do
    Logger.info("Voice call rejected: user=#{socket.assigns.current_user.id}")
    {:noreply, assign(socket, call_status: "rejected")}
  end

  # Handle call ended event
  def handle_info(%{event: "call_ended"}, socket) do
    Logger.info("Voice call ended by peer: user=#{socket.assigns.current_user.id}")
    {:noreply, assign(socket, call_status: "ended")}
  end

  # ==========================
  # Component Functions
  # ==========================

  def render(assigns) do
    assigns = assign(assigns, :caller, Map.get(assigns, :caller))

    ~H"""
    <div class="relative min-h-screen bg-gray-100 flex flex-col w-full">
      <.voice_header {assigns} />
      <.main_content {assigns} />
    </div>
    """
  end

  defp voice_header(assigns) do
    ~H"""
    <div class="absolute top-0 left-0 right-0 bg-white shadow-sm border-b border-gray-200 py-4 z-10">
      <div class="max-w-md mx-auto px-4 flex justify-between items-center">
        <.header_title call_status={@call_status} caller={@caller} target_user={@target_user} />
        <.header_actions call_status={@call_status} current_user={@current_user} />
      </div>
    </div>
    """
  end

  defp header_title(assigns) do
    ~H"""
    <div class="flex items-center">
      <h1 class="text-xl font-bold text-gray-800">Voice Chat</h1>
      <div class="ml-3 text-sm text-gray-600">
        {chat_partner_text(@call_status, @caller, @target_user)}
      </div>
    </div>
    """
  end

  defp header_actions(assigns) do
    ~H"""
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
    """
  end

  defp main_content(assigns) do
    ~H"""
    <div class="w-full flex items-center justify-center min-h-screen pt-20">
      <div class="bg-white rounded-lg shadow-md p-8 max-w-md w-full mx-auto">
        <div class="text-center">
          <.status_badge call_status={@call_status} />
          <.audio_visualizer call_status={@call_status} />
          <.voice_chat_container
            call_status={@call_status}
            current_user={@current_user}
            target_user_id={@target_user_id}
            call_id={@call_id}
            caller={@caller}
            target_user={@target_user}
          />
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    assigns = assign(assigns, :status_info, status_info(assigns.call_status))

    ~H"""
    <div class={"call-status-badge mb-6 #{elem(@status_info, 0)}"}>
      {elem(@status_info, 1)}
    </div>
    """
  end

  defp audio_visualizer(assigns) do
    assigns = assign(assigns, :bg_color, status_bg_color(assigns.call_status))

    ~H"""
    <div class="mb-8">
      <div class={"w-32 h-32 rounded-full flex items-center justify-center mx-auto #{@bg_color}"}>
        <.icon name="hero-microphone" class="h-16 w-16 text-gray-500" />
      </div>
      <%= if @call_status == "connected" do %>
        <div class="audio-wave mt-4">
          <span></span> <span></span> <span></span> <span></span> <span></span>
        </div>
      <% end %>
    </div>
    """
  end

  defp voice_chat_container(assigns) do
    ~H"""
    <div
      id="voice-chat-container"
      phx-hook="VoiceChat"
      data-user-id={@current_user.id}
      data-target-id={@target_user_id}
      data-call-id={@call_id}
      data-call-status={@call_status}
      class="flex flex-col items-center justify-center"
    >
      <.action_buttons call_status={@call_status} />
    </div>
    """
  end

  defp action_buttons(assigns) do
    ~H"""
    <div class="mt-4 text-center">
      <%= case @call_status do %>
        <% "init" -> %>
          <button
            phx-click="request_call"
            class="bg-blue-500 hover:bg-blue-600 text-white px-8 py-3 rounded-full text-lg"
          >
            Start Call
          </button>
        <% "incoming" -> %>
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
        <% status when status in ["rejected", "ended"] -> %>
          <button
            phx-click="end_call"
            class="bg-gray-500 hover:bg-gray-600 text-white px-8 py-3 rounded-full text-lg"
          >
            Close
          </button>
        <% status -> %>
          <%= if error_status?(status) do %>
            <div>
              <div class="mb-4 text-red-600 text-sm">
                {String.replace_prefix(status, "error: ", "")}
              </div>
              <button
                phx-click="request_call"
                class="bg-blue-500 hover:bg-blue-600 text-white px-8 py-3 rounded-full text-lg"
              >
                Try Again
              </button>
            </div>
          <% else %>
            <!-- No buttons for other states -->
          <% end %>
      <% end %>
    </div>
    """
  end

  defp error_status?(status) when is_binary(status) do
    String.starts_with?(status, "error:")
  end

  defp error_status?(_), do: false

  # ==========================
  # Button Components
  # ==========================

  # Button components are now inlined in action_buttons/1 for better performance
  # and to avoid unused function warnings. Keeping the section for future extensibility.

  # ==========================
  # Utility Functions
  # ==========================

  defp chat_partner_text("incoming", caller, _target_user) do
    "from #{caller.username}"
  end

  defp chat_partner_text(_status, _caller, target_user) do
    "with #{target_user.username}"
  end

  defp topic_user(user_id), do: "voice:#{user_id}"
  defp topic_call(call_id), do: "voice_call:#{call_id}"

  # ==========================
  # Broadcasting Helpers
  # ==========================

  defp broadcast_call_request(target_user_id, current_user, call_id) do
    SlapWeb.Endpoint.broadcast(topic_user(target_user_id), "voice_call_request", %{
      from_user_id: current_user.id,
      from_username: current_user.username,
      call_id: call_id
    })
  end

  defp broadcast_call_accepted(call_id, user_id) do
    SlapWeb.Endpoint.broadcast(topic_call(call_id), "call_accepted", %{by_user_id: user_id})
  end

  defp broadcast_call_rejected(call_id, user_id) do
    SlapWeb.Endpoint.broadcast(topic_call(call_id), "call_rejected", %{by_user_id: user_id})
  end

  defp broadcast_voice_signal(call_id, signal_data, from_user_id) do
    SlapWeb.Endpoint.broadcast(topic_call(call_id), "voice_signal", %{
      signal: signal_data,
      from: from_user_id
    })
  end

  defp broadcast_call_ended(call_id, user_id) do
    SlapWeb.Endpoint.broadcast(topic_call(call_id), "call_ended", %{by_user_id: user_id})
  end

  defp close_window(socket) do
    {:noreply, push_event(socket, "close_window", %{})}
  end

  defp initiate_webrtc_connection(socket, initiator) do
    {:noreply,
     socket
     |> assign(call_status: "connecting", call_role: "callee")
     |> push_event("voice:initialize", %{initiator: initiator})}
  end

  # ==========================
  # Helper Functions
  # ==========================

  defp generate_call_id(user_id1, user_id2) do
    "#{min(user_id1, user_id2)}_#{max(user_id1, user_id2)}"
  end

  defp setup_subscriptions(socket, user_id, call_id) do
    if connected?(socket) do
      SlapWeb.Endpoint.subscribe(topic_user(user_id))
      SlapWeb.Endpoint.subscribe(topic_call(call_id))
    end

    socket
  end

  defp handle_accepted_call_mount(socket, current_user_id, call_id) do
    broadcast_call_accepted(call_id, current_user_id)

    {:ok,
     socket
     |> assign(call_status: "connecting", call_role: "callee")
     |> push_event("voice:initialize", %{initiator: false})}
  end

  defp get_target_user(user_id_param) when is_binary(user_id_param) do
    case Integer.parse(user_id_param) do
      {user_id, ""} ->
        try do
          user = Slap.Accounts.get_user!(user_id)
          {:ok, user}
        rescue
          Ecto.NoResultsError -> {:error, :user_not_found}
        end

      _ ->
        {:error, :invalid_user_id}
    end
  end

  # ==========================
  # Status Helpers
  # ==========================

  defp status_info(status) when is_binary(status) do
    cond do
      String.starts_with?(status, "error:") ->
        {"bg-red-100 text-red-800", "Error: #{String.replace_prefix(status, "error: ", "")}"}

      Map.has_key?(@status_messages, status) ->
        {@status_colors[status], @status_messages[status]}

      true ->
        {"bg-gray-100 text-gray-800", status}
    end
  end

  # Status helper functions - status_message/1 and status_color/1 are now unused
  # since we use status_info/1 directly in components for better performance

  defp status_bg_color(status) when is_binary(status) do
    Map.get(@status_bg_colors, status, "bg-gray-200")
  end
end
