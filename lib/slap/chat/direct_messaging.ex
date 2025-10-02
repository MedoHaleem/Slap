defmodule Slap.Chat.DirectMessaging do
  @moduledoc """
  Wrapper module for Slap.DirectMessaging to provide a consistent API
  within the Chat context.
  """

  # Delegate all the required functions to Slap.DirectMessaging
  defdelegate count_unread_messages(conversation_id, user_id), to: Slap.DirectMessaging
  defdelegate mark_conversation_read(conversation, user), to: Slap.DirectMessaging
  defdelegate send_direct_message(conversation, attrs, user), to: Slap.DirectMessaging
  defdelegate get_direct_message!(id, opts \\ []), to: Slap.DirectMessaging
  defdelegate get_conversation_participant(conversation_id, user_id), to: Slap.DirectMessaging
  defdelegate update_direct_message(direct_message, attrs, user), to: Slap.DirectMessaging
  defdelegate delete_direct_message(direct_message, user), to: Slap.DirectMessaging
end
