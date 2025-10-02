defmodule Slap.Boundaries do
  @moduledoc """
  Defines the boundaries and interactions between contexts in the Slap application.
  Ensures proper separation of concerns and clear interfaces between modules.
  """

  @doc """
  Defines the allowed interactions between contexts.
  Returns a map of context pairs to allowed interactions.
  """
  def allowed_interactions do
    %{
      # Accounts context interactions
      {:accounts, :chat} => [:get_user, :get_user_by_username],
      {:accounts, :direct_messaging} => [:get_user, :get_user_by_username],

      # Chat context interactions
      {:chat, :accounts} => [:get_user, :get_user_by_username],
      {:chat, :uploads} => [:store_file, :delete_file],

      # DirectMessaging context interactions
      {:direct_messaging, :accounts} => [:get_user, :get_user_by_username],
      {:direct_messaging, :uploads} => [:store_file, :delete_file],

      # Uploads context interactions
      {:uploads, :accounts} => [:get_user],

      # Web layer interactions
      {:web, :accounts} => [:get_user, :get_user_by_username, :authenticate_user],
      {:web, :chat} => [:list_rooms, :get_room, :create_message, :list_messages],
      {:web, :direct_messaging} => [:list_conversations, :get_conversation, :send_message],
      {:web, :uploads} => [:upload_file, :delete_file]
    }
  end

  @doc """
  Checks if an interaction between contexts is allowed.
  """
  def interaction_allowed?(source_context, target_context, interaction) do
    interactions = allowed_interactions()

    case Map.get(interactions, {source_context, target_context}) do
      nil -> false
      allowed_interactions -> interaction in allowed_interactions
    end
  end

  @doc """
  Defines the data ownership rules for each context.
  Returns a map of contexts to their owned data types.
  """
  def data_ownership do
    %{
      accounts: [:users, :sessions],
      chat: [:rooms, :messages, :replies, :reactions, :room_memberships, :message_attachments],
      direct_messaging: [:conversations, :direct_messages, :conversation_participants,
                        :conversation_invites, :conversation_settings],
      uploads: [:files]
    }
  end

  @doc """
  Checks if a context owns a specific data type.
  """
  def owns_data?(context, data_type) do
    ownership = data_ownership()
    data_type in Map.get(ownership, context, [])
  end

  @doc """
  Defines the public API for each context.
  Returns a map of contexts to their public functions.
  """
  def public_apis do
    %{
      accounts: %{
        users: [:get_user, :get_user_by_username, :create_user, :update_user, :delete_user, :authenticate_user],
        sessions: [:create_session, :delete_session, :get_session]
      },
      chat: %{
        rooms: [:list_rooms, :get_room, :create_room, :update_room, :delete_room, :join_room, :leave_room],
        messages: [:list_messages, :get_message, :create_message, :update_message, :delete_message],
        reactions: [:add_reaction, :remove_reaction],
        replies: [:create_reply, :update_reply, :delete_reply]
      },
      direct_messaging: %{
        conversations: [:list_conversations, :get_conversation, :create_conversation, :update_conversation,
                         :delete_conversation, :get_conversation_between_users],
        messages: [:list_direct_messages, :get_direct_message, :send_direct_message, :update_direct_message,
                  :delete_direct_message],
        participants: [:add_participant, :remove_participant, :promote_participant],
        invitations: [:create_conversation_invite, :accept_conversation_invite, :decline_conversation_invite]
      },
      uploads: %{
        files: [:upload_file, :delete_file, :get_file]
      }
    }
  end

  @doc """
  Checks if a function is part of the public API of a context.
  """
  def public_function?(context, module, function) do
    apis = public_apis()

    case Map.get(apis, context) do
      nil -> false
      context_modules ->
        case Map.get(context_modules, module) do
          nil -> false
          functions -> function in functions
        end
    end
  end

  @doc """
  Defines the event publishing rules for each context.
  Returns a map of contexts to their published events.
  """
  def event_publishing do
    %{
      accounts: [:user_created, :user_updated, :user_deleted, :user_signed_in, :user_signed_out],
      chat: [:room_created, :room_updated, :room_deleted, :message_created, :message_updated, :message_deleted,
             :reaction_added, :reaction_removed, :reply_created, :reply_deleted],
      direct_messaging: [:conversation_created, :conversation_updated, :conversation_deleted, :message_sent,
                        :message_updated, :message_deleted, :participant_added, :participant_removed,
                        :invitation_sent, :invitation_accepted, :invitation_declined],
      uploads: [:file_uploaded, :file_deleted]
    }
  end

  @doc """
  Checks if a context is allowed to publish a specific event.
  """
  def can_publish_event?(context, event) do
    publishing = event_publishing()
    event in Map.get(publishing, context, [])
  end
end
