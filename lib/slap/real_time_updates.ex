defmodule Slap.RealTimeUpdates do
  @moduledoc """
  A unified module for handling real-time updates across the application.
  Provides consistent patterns for subscribing to and broadcasting updates.
  """

  alias Slap.PubSub
  alias Slap.Constants

  @doc """
  Subscribe to a topic with a consistent pattern.
  """
  def subscribe(topic_type, topic_id) do
    Phoenix.PubSub.subscribe(PubSub, Constants.pubsub_topic(topic_type, topic_id))
  end

  @doc """
  Unsubscribe from a topic.
  """
  def unsubscribe(topic_type, topic_id) do
    Phoenix.PubSub.unsubscribe(PubSub, Constants.pubsub_topic(topic_type, topic_id))
  end

  @doc """
  Broadcast a message to a topic with error handling.
  """
  def broadcast(topic_type, topic_id, event, payload) do
    topic = Constants.pubsub_topic(topic_type, topic_id)

    try do
      Phoenix.PubSub.broadcast!(PubSub, topic, {event, payload})
      :ok
    rescue
      error ->
        require Logger
        Logger.error("Failed to broadcast to #{topic}: #{inspect(error)}")
        {:error, :broadcast_failed}
    end
  end

  @doc """
  Broadcast a message to a topic asynchronously.
  """
  def broadcast_async(topic_type, topic_id, event, payload) do
    topic = Constants.pubsub_topic(topic_type, topic_id)
    Phoenix.PubSub.broadcast(PubSub, topic, {event, payload})
  end

  @doc """
  Handle new message updates for both rooms and conversations.
  """
  def handle_new_message(message, message_type, current_user_id) do
    # Mark as read if sent by current user
    if message.user_id == current_user_id do
      mark_message_read(message, message_type, current_user_id)
    end

    # Broadcast the message
    broadcast(message_type, get_message_container_id(message), :new_message, message)
  end

  @doc """
  Handle message deletion updates.
  """
  def handle_message_deleted(message, message_type) do
    broadcast(message_type, get_message_container_id(message), :message_deleted, message)
  end

  @doc """
  Handle conversation/room updates.
  """
  def handle_container_updated(container, container_type) do
    broadcast(container_type, container.id, :container_updated, container)
  end

  @doc """
  Handle user presence updates.
  """
  def handle_user_presence_update(user_id, presence_type, payload) do
    broadcast(:presence, user_id, presence_type, payload)
  end

  # Private helper functions

  defp get_message_container_id(%{room_id: room_id}), do: room_id
  defp get_message_container_id(%{conversation_id: conversation_id}), do: conversation_id
  defp get_message_container_id(_), do: nil

  defp mark_message_read(message, :room, user_id) do
    Slap.Chat.update_last_read_id(%Slap.Chat.Room{id: message.room_id}, %Slap.Accounts.User{
      id: user_id
    })
  end

  defp mark_message_read(message, :conversation, user_id) do
    Slap.DirectMessaging.mark_conversation_read(
      %Slap.Chat.Conversation{id: message.conversation_id},
      %Slap.Accounts.User{id: user_id}
    )
  end
end
