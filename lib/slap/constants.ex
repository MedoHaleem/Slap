defmodule Slap.Constants do
  @moduledoc """
  Centralized constants for the Slap application.
  This module eliminates magic numbers and strings throughout the codebase.
  """

  # Rate limiting constants
  @default_message_limit 50
  @rate_limit_window 60_000  # 1 minute in milliseconds
  @rate_limit_max_messages 30
  @heartbeat_interval 30_000  # 30 seconds in milliseconds

  # Conversation constants
  @max_participants 100
  @max_group_conversation_name_length 50
  @max_direct_conversation_name_length 30

  # File upload constants
  @max_file_size 10_000_000  # 10MB in bytes
  @allowed_file_extensions ~w(.pdf)

  # Pagination constants
  @default_page_size 20
  @max_page_size 100

  # Search constants
  @default_search_limit 20
  @max_search_results 50

  # UI constants
  @debounce_timeout 300  # milliseconds
  @typing_indicator_timeout 5_000  # milliseconds

  # Time constants
  @message_timestamp_format "%I:%M %p"
  @date_format "%b %d, %Y"
  @datetime_format "%b %d, %Y at %H:%M"

  # Role constants
  @roles ~w(admin moderator member restricted)
  @role_permissions %{
    "admin" => [
      :manage_settings,
      :add_participants,
      :remove_participants,
      :delete_any_message,
      :promote_participants,
      :demote_participants,
      :delete_conversation,
      :kick_participants,
      :mute_participants
    ],
    "moderator" => [
      :manage_settings,
      :add_participants,
      :remove_participants,
      :delete_messages,
      :kick_participants,
      :mute_participants
    ],
    "member" => [
      :send_messages,
      :react_to_messages,
      :view_participants,
      :leave_conversation,
      :invite_participants
    ],
    "restricted" => [
      :view_messages,
      :leave_conversation
    ]
  }

  # Conversation types
  @conversation_types ~w(direct group channel)

  # CSS class constants
  @css %{
    primary_button: "px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500",
    secondary_button: "px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-500",
    danger_button: "px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500",
    success_button: "px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-green-500",
    input_field: "border border-gray-300 rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500",
    avatar: "w-8 h-8 rounded-full",
    small_avatar: "w-6 h-6 rounded-full",
    large_avatar: "w-16 h-16 rounded-full",
    unread_badge: "ml-2 flex-shrink-0 bg-red-500 text-white text-xs font-medium px-2 py-1 rounded-full",
    online_indicator: "w-3 h-3 bg-green-400 rounded-full border-2 border-white",
    offline_indicator: "w-3 h-3 bg-gray-400 rounded-full border-2 border-white",
    message_container: "flex items-start space-x-3",
    message_content: "flex-1",
    message_timestamp: "text-xs text-gray-500",
    message_body: "text-gray-900 mt-1",
    search_highlight: "bg-yellow-200 text-yellow-800 px-1 rounded",
    role_badges: %{
      "admin" => "bg-red-100 text-red-800 text-xs font-medium px-2 py-1 rounded-full",
      "moderator" => "bg-yellow-100 text-yellow-800 text-xs font-medium px-2 py-1 rounded-full",
      "member" => "bg-green-100 text-green-800 text-xs font-medium px-2 py-1 rounded-full",
      "restricted" => "bg-gray-100 text-gray-800 text-xs font-medium px-2 py-1 rounded-full"
    }
  }

  # PubSub topic patterns
  @pubsub_topics %{
    room: "chat_room:",
    conversation: "conversation:",
    direct_messages: "direct_messages:",
    voice: "voice:",
    voice_call: "voice_call:",
    presence: "presence:"
  }

  # Error messages
  @error_messages %{
    rate_limit_exceeded: "Message rate limit exceeded. Please wait before sending another message.",
    not_participant: "User is not a participant in this conversation",
    insufficient_permissions: "You don't have permission to perform this action",
    conversation_not_found: "Conversation not found",
    message_not_found: "Message not found",
    user_not_found: "User not found",
    invalid_invite: "Invalid or expired invitation",
    invite_expired: "Invitation has expired",
    already_participant: "User is already a participant in this conversation",
    max_participants_reached: "Maximum number of participants reached",
    invalid_role: "Invalid role specified",
    cannot_promote_to_same_or_lower: "Cannot promote to same or lower role"
  }

  # Success messages
  @success_messages %{
    message_sent: "Message sent successfully",
    invitation_sent: "Invitation sent successfully",
    invitation_accepted: "Successfully joined conversation",
    invitation_declined: "Invitation declined",
    conversation_left: "You have left the conversation",
    conversation_updated: "Conversation updated successfully",
    participant_promoted: "Participant promoted successfully",
    participant_added: "Participant added successfully",
    participant_removed: "Participant removed successfully"
  }

  # Getter functions for constants
  def default_message_limit, do: @default_message_limit
  def rate_limit_window, do: @rate_limit_window
  def rate_limit_max_messages, do: @rate_limit_max_messages
  def heartbeat_interval, do: @heartbeat_interval
  def max_participants, do: @max_participants
  def max_group_conversation_name_length, do: @max_group_conversation_name_length
  def max_direct_conversation_name_length, do: @max_direct_conversation_name_length
  def max_file_size, do: @max_file_size
  def allowed_file_extensions, do: @allowed_file_extensions
  def default_page_size, do: @default_page_size
  def max_page_size, do: @max_page_size
  def default_search_limit, do: @default_search_limit
  def max_search_results, do: @max_search_results
  def debounce_timeout, do: @debounce_timeout
  def typing_indicator_timeout, do: @typing_indicator_timeout
  def message_timestamp_format, do: @message_timestamp_format
  def date_format, do: @date_format
  def datetime_format, do: @datetime_format
  def roles, do: @roles
  def role_permissions, do: @role_permissions
  def conversation_types, do: @conversation_types
  def css, do: @css
  def pubsub_topics, do: @pubsub_topics
  def error_messages, do: @error_messages
  def success_messages, do: @success_messages

  # Helper functions
  def role_has_permission?(role, permission) do
    permissions = Map.get(@role_permissions, role, [])
    permission in permissions
  end

  def valid_role?(role), do: role in @roles

  def valid_conversation_type?(type), do: type in @conversation_types

  def get_css_class(key) do
    Map.get(@css, key, "")
  end

  def get_role_badge_class(role) do
    Map.get(@css.role_badges, role, "")
  end

  def get_error_message(key) do
    Map.get(@error_messages, key, "An error occurred")
  end

  def get_success_message(key) do
    Map.get(@success_messages, key, "Operation completed successfully")
  end

  def pubsub_topic(:room, id), do: @pubsub_topics.room <> to_string(id)
  def pubsub_topic(:conversation, id), do: @pubsub_topics.conversation <> to_string(id)
  def pubsub_topic(:direct_messages, id), do: @pubsub_topics.direct_messages <> to_string(id)
  def pubsub_topic(:voice, id), do: @pubsub_topics.voice <> to_string(id)
  def pubsub_topic(:voice_call, id), do: @pubsub_topics.voice_call <> to_string(id)
  def pubsub_topic(:presence, id), do: @pubsub_topics.presence <> to_string(id)
end
