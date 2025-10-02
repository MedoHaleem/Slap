defmodule Slap.Authorization do
  @moduledoc """
  Unified authorization system for Slap application.
  Provides role-based access control and permission checking.
  """

  alias Slap.Accounts.User
  alias Slap.Chat.{Room, RoomMembership}
  alias Slap.Chat.{Conversation, ConversationParticipant}
  alias Slap.Constants

  @type permission :: atom()
  @type resource :: any()
  @type context :: map()

  # Room permissions
  @room_permissions %{
    "owner" => [
      :manage_room, :delete_room, :kick_members, :promote_to_admin,
      :send_messages, :read_messages, :react_to_messages, :edit_own_messages,
      :delete_own_messages, :view_members, :invite_members
    ],
    "admin" => [
      :manage_room, :kick_members, :promote_to_admin,
      :send_messages, :read_messages, :react_to_messages, :edit_own_messages,
      :delete_own_messages, :view_members, :invite_members
    ],
    "member" => [
      :send_messages, :read_messages, :react_to_messages, :edit_own_messages,
      :delete_own_messages, :view_members
    ]
  }

  # Conversation permissions are defined in Constants.role_permissions/0

  @doc """
  Checks if a user has a specific permission for a room.
  """
  @spec can_access_room?(User.t(), Room.t(), permission()) :: boolean()
  def can_access_room?(user, room, permission) do
    case get_room_role(user, room) do
      nil -> false
      role -> has_permission?(role, permission, @room_permissions)
    end
  end

  @doc """
  Checks if a user has a specific permission for a conversation.
  """
  @spec can_access_conversation?(User.t(), Conversation.t(), permission()) :: boolean()
  def can_access_conversation?(user, conversation, permission) do
    case get_conversation_role(user, conversation) do
      {:ok, role} -> Constants.role_has_permission?(role, permission)
      {:error, _reason} -> false
    end
  end

  @doc """
  Checks if a user can send messages in a room.
  """
  @spec can_send_room_message?(User.t(), Room.t()) :: boolean()
  def can_send_room_message?(user, room) do
    can_access_room?(user, room, :send_messages)
  end

  @doc """
  Checks if a user can send messages in a conversation.
  """
  @spec can_send_conversation_message?(User.t(), Conversation.t()) :: boolean()
  def can_send_conversation_message?(user, conversation) do
    can_access_conversation?(user, conversation, :send_messages)
  end

  @doc """
  Checks if a user can manage a room (change settings, kick members, etc.).
  """
  @spec can_manage_room?(User.t(), Room.t()) :: boolean()
  def can_manage_room?(user, room) do
    can_access_room?(user, room, :manage_room)
  end

  @doc """
  Checks if a user can manage a conversation (change settings, kick members, etc.).
  """
  @spec can_manage_conversation?(User.t(), Conversation.t()) :: boolean()
  def can_manage_conversation?(user, conversation) do
    can_access_conversation?(user, conversation, :manage_settings)
  end

  @doc """
  Checks if a user can delete any message in a room.
  """
  @spec can_delete_any_room_message?(User.t(), Room.t()) :: boolean()
  def can_delete_any_room_message?(user, room) do
    can_access_room?(user, room, :delete_any_message)
  end

  @doc """
  Checks if a user can delete any message in a conversation.
  """
  @spec can_delete_any_conversation_message?(User.t(), Conversation.t()) :: boolean()
  def can_delete_any_conversation_message?(user, conversation) do
    can_access_conversation?(user, conversation, :delete_any_message)
  end

  @doc """
  Checks if a user can edit their own message in a room.
  """
  @spec can_edit_own_room_message?(User.t(), Room.t()) :: boolean()
  def can_edit_own_room_message?(user, room) do
    can_access_room?(user, room, :edit_own_messages)
  end

  @doc """
  Checks if a user can edit their own message in a conversation.
  """
  @spec can_edit_own_conversation_message?(User.t(), Conversation.t()) :: boolean()
  def can_edit_own_conversation_message?(user, conversation) do
    can_access_conversation?(user, conversation, :edit_messages)
  end

  @doc """
  Checks if a user can invite others to a conversation.
  """
  @spec can_invite_to_conversation?(User.t(), Conversation.t()) :: boolean()
  def can_invite_to_conversation?(user, conversation) do
    can_access_conversation?(user, conversation, :invite_participants)
  end

  @doc """
  Checks if a user can promote/demote participants in a conversation.
  """
  @spec can_manage_participants?(User.t(), Conversation.t()) :: boolean()
  def can_manage_participants?(user, conversation) do
    can_access_conversation?(user, conversation, :promote_participants)
  end

  @doc """
  Gets all permissions a user has for a room.
  """
  @spec get_room_permissions(User.t(), Room.t()) :: [permission()]
  def get_room_permissions(user, room) do
    case get_room_role(user, room) do
      nil -> []
      role -> Map.get(@room_permissions, role, [])
    end
  end

  @doc """
  Gets all permissions a user has for a conversation.
  """
  @spec get_conversation_permissions(User.t(), Conversation.t()) :: [permission()]
  def get_conversation_permissions(user, conversation) do
    case get_conversation_role(user, conversation) do
      {:ok, role} -> Map.get(Constants.role_permissions(), role, [])
      {:error, _reason} -> []
    end
  end

  @doc """
  Checks if a user is the owner of a room.
  """
  @spec is_room_owner?(User.t(), Room.t()) :: boolean()
  def is_room_owner?(user, room) do
    get_room_role(user, room) == "owner"
  end

  @doc """
  Checks if a user is an admin in a conversation.
  """
  @spec is_conversation_admin?(User.t(), Conversation.t()) :: boolean()
  def is_conversation_admin?(user, conversation) do
    case get_conversation_role(user, conversation) do
      {:ok, "admin"} -> true
      _ -> false
    end
  end

  @doc """
  Checks if a user is a moderator in a conversation.
  """
  @spec is_conversation_moderator?(User.t(), Conversation.t()) :: boolean()
  def is_conversation_moderator?(user, conversation) do
    case get_conversation_role(user, conversation) do
      {:ok, "moderator"} -> true
      _ -> false
    end
  end

  @doc """
  Validates a role promotion in a conversation.
  Returns :ok if valid, {:error, reason} otherwise.
  """
  @spec validate_role_promotion(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_role_promotion(current_role, new_role) do
    role_hierarchy = %{
      "restricted" => 0,
      "member" => 1,
      "moderator" => 2,
      "admin" => 3
    }

    current_level = Map.get(role_hierarchy, current_role, -1)
    new_level = Map.get(role_hierarchy, new_role, -1)

    if new_level > current_level do
      :ok
    else
      {:error, Constants.get_error_message(:cannot_promote_to_same_or_lower)}
    end
  end

  # Private functions

  defp get_room_role(user, room) do
    import Ecto.Query

    query =
      from m in RoomMembership,
        where: m.user_id == ^user.id and m.room_id == ^room.id,
        select: m.role

    Slap.Repo.one(query)
  end

  defp get_conversation_role(user, conversation) do
    import Ecto.Query

    query =
      from p in ConversationParticipant,
        where: p.user_id == ^user.id and p.conversation_id == ^conversation.id,
        select: p.role

    case Slap.Repo.one(query) do
      nil -> {:error, Constants.get_error_message(:not_participant)}
      role -> {:ok, role}
    end
  end

  defp has_permission?(role, permission, permission_map) do
    permissions = Map.get(permission_map, role, [])
    permission in permissions
  end
end
