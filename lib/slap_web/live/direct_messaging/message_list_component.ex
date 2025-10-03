defmodule SlapWeb.DirectMessaging.MessageListComponent do
  use SlapWeb, :live_component
  import SlapWeb.UIHelpers

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dm-messages-container flex-1 overflow-y-auto p-4 space-y-4" id="messages-container">
      <%= for message <- @messages do %>
        <.message_container>
          <.user_avatar user={message.user} size="normal" />
          <.message_content>
            <div class="flex items-center space-x-2">
              <span class="text-sm font-medium text-gray-900">
                {message.user.username}
              </span>

              <.message_timestamp timestamp={message.inserted_at} />
            </div>

            <.message_body body={message.body} />
          </.message_content>
        </.message_container>
      <% end %>
    </div>

    <script>
      // Scroll to bottom of messages container
      const messagesContainer = document.getElementById('messages-container');
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    </script>
    """
  end
end
