defmodule Slap.GroupConversationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Slap.DirectMessaging` context for group conversations.
  """

  alias Slap.DirectMessaging

  @doc """
  Generate a group conversation with participants.
  """
  def group_conversation_fixture(attrs \\ %{}) do
    participants = Map.get(attrs, :participants, [])

    # Create default participants if none provided
    participants =
      if Enum.empty?(participants) do
        [user_fixture(), user_fixture(), user_fixture()]
      else
        participants
      end

    # Create creator (first participant)
    creator = hd(participants)

    # Create conversation attributes
    conversation_attrs =
      attrs
      |> Map.drop([:participants])
      |> Enum.into(%{
        title: "Test Group #{System.unique_integer([:positive])}",
        type: "group",
        is_public: false
      })

    {:ok, conversation} = DirectMessaging.create_group_conversation(
      conversation_attrs,
      participants,
      creator
    )

    conversation
  end

  @doc """
  Generate a public group conversation.
  """
  def public_group_conversation_fixture(attrs \\ %{}) do
    attrs = Map.merge(attrs, %{is_public: true})
    group_conversation_fixture(attrs)
  end

  @doc """
  Generate a group conversation with specific roles.
  """
  def group_conversation_with_roles_fixture(attrs \\ %{}) do
    admin = Map.get(attrs, :admin, user_fixture())
    moderator = Map.get(attrs, :moderator, user_fixture())
    member = Map.get(attrs, :member, user_fixture())

    participants = [admin, moderator, member]

    conversation = group_conversation_fixture(Map.merge(attrs, %{participants: participants}))

    # Set moderator role
    {:ok, _} = DirectMessaging.promote_participant(conversation, moderator.id, "moderator", admin)

    conversation
  end

  @doc """
  Generate a conversation invitation.
  """
  def conversation_invite_fixture(attrs \\ %{}) do
    conversation = Map.get(attrs, :conversation) || group_conversation_fixture()
    inviter = Map.get(attrs, :inviter) ||
              Enum.find(conversation.conversation_participants, &(&1.role in ["admin", "moderator"]))
              |> Map.get(:user) || user_fixture()
    invitee = Map.get(attrs, :invitee) || user_fixture()

    _attrs =
      attrs
      |> Map.drop([:conversation, :inviter, :invitee])
      |> Enum.into(%{})

    {:ok, invite} = DirectMessaging.create_conversation_invite(
      conversation,
      invitee.id,
      inviter
    )

    invite
  end

  @doc """
  Generate conversation settings.
  """
  def conversation_setting_fixture(attrs \\ %{}) do
    conversation = Map.get(attrs, :conversation) || group_conversation_fixture()

    attrs =
      attrs
      |> Map.drop([:conversation])
      |> Enum.into(%{
        allow_participant_invites: true,
        require_admin_approval: false,
        message_editing_enabled: true,
        file_sharing_enabled: true,
        max_participants: 100
      })

    {:ok, settings} = DirectMessaging.update_conversation_settings(
      conversation,
      attrs,
      hd(conversation.conversation_participants).user
    )

    settings
  end

  @doc """
  Generate a conversation participant with specific role.
  """
  def conversation_participant_fixture(attrs \\ %{}) do
    conversation = Map.get(attrs, :conversation) || group_conversation_fixture()
    user = Map.get(attrs, :user) || user_fixture()
    role = Map.get(attrs, :role, "member")

    # Add participant if not already in conversation
    case DirectMessaging.get_conversation_participant(conversation.id, user.id) do
      nil ->
        {:ok, participant} = DirectMessaging.add_participant_to_conversation(conversation, user.id)

        # Update role if not default
        if role != "member" do
          admin_participant = Enum.find(conversation.conversation_participants, &(&1.role == "admin"))
          admin = admin_participant.user
          {:ok, participant} = DirectMessaging.promote_participant(conversation, user.id, role, admin)
          participant
        else
          participant
        end

      existing_participant ->
        existing_participant
    end
  end

  @doc """
  Generate a direct message conversation (for backward compatibility testing).
  """
  def direct_message_conversation_fixture(attrs \\ %{}) do
    user1 = Map.get(attrs, :user1) || user_fixture()
    user2 = Map.get(attrs, :user2) || user_fixture()

    attrs =
      attrs
      |> Map.drop([:user1, :user2])
      |> Enum.into(%{})

    {:ok, conversation} = DirectMessaging.create_direct_message_conversation(
      attrs,
      user1,
      user2
    )

    conversation
  end

  @doc """
  Helper to create multiple users for testing.
  """
  def create_users(count, prefix \\ "user") do
    for i <- 1..count do
      user_fixture(%{username: "#{prefix}#{i}"})
    end
  end

  @doc """
  Helper to create a conversation with many participants for scalability testing.
  """
  def large_group_conversation_fixture(participant_count \\ 50) do
    users = create_users(participant_count, "large_user")
    _creator = hd(users)

    group_conversation_fixture(%{
      participants: users,
      title: "Large Group #{participant_count} Participants"
    })
  end

  @doc """
  Helper to create pending invitations for a user.
  """
  def pending_invitations_fixture(user, count \\ 3) do
    for i <- 1..count do
      inviter = user_fixture(%{username: "inviter#{i}"})
      conversation = group_conversation_fixture(%{participants: [inviter]})

      conversation_invite_fixture(%{
        conversation: conversation,
        inviter: inviter,
        invitee: user
      })
    end
  end

  # Import the user_fixture from accounts fixtures
  defp user_fixture(attrs \\ %{}) do
    Slap.AccountsFixtures.user_fixture(attrs)
  end
end
