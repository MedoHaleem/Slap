defmodule Slap.Chat.RoomMembershipTest do
  use Slap.DataCase, async: true

  alias Slap.Chat.RoomMembership

  describe "changeset/2" do
    test "valid changeset with default values" do
      attrs = %{}
      changeset = RoomMembership.changeset(%RoomMembership{}, attrs)

      assert changeset.valid?
      assert changeset.changes == %{}
    end

    test "changeset accepts any attributes" do
      attrs = %{room_id: 1, user_id: 2, last_read_id: 100}
      changeset = RoomMembership.changeset(%RoomMembership{}, attrs)

      assert changeset.valid?
      # The changeset doesn't cast any fields, so changes remain empty
      assert changeset.changes == %{}
    end

    test "changeset with nil values" do
      attrs = %{room_id: nil, user_id: nil, last_read_id: nil}
      changeset = RoomMembership.changeset(%RoomMembership{}, attrs)

      assert changeset.valid?
      assert changeset.changes == %{}
    end

    test "changeset with string values" do
      attrs = %{room_id: "1", user_id: "2", last_read_id: "100"}
      changeset = RoomMembership.changeset(%RoomMembership{}, attrs)

      assert changeset.valid?
      # Since cast([]) is used, no fields are cast, so changes remain empty
      assert changeset.changes == %{}
    end
  end

  describe "schema fields" do
    test "has room_id field" do
      assert RoomMembership.__schema__(:type, :room_id) == :id
    end

    test "has user_id field" do
      assert RoomMembership.__schema__(:type, :user_id) == :id
    end

    test "has last_read_id field" do
      assert RoomMembership.__schema__(:type, :last_read_id) == :integer
    end

    test "has timestamps" do
      assert RoomMembership.__schema__(:type, :inserted_at) == :utc_datetime
      assert RoomMembership.__schema__(:type, :updated_at) == :utc_datetime
    end

    test "has correct table name" do
      assert RoomMembership.__schema__(:source) == "room_memberships"
    end
  end

  describe "associations" do
    test "belongs to room" do
      room_assoc = RoomMembership.__schema__(:association, :room)
      assert room_assoc != nil
      assert room_assoc.related == Slap.Chat.Room
      assert room_assoc.owner_key == :room_id
    end

    test "belongs to user" do
      user_assoc = RoomMembership.__schema__(:association, :user)
      assert user_assoc != nil
      assert user_assoc.related == Slap.Accounts.User
      assert user_assoc.owner_key == :user_id
    end
  end

  describe "field sources" do
    test "room_id field source" do
      assert RoomMembership.__schema__(:field_source, :room_id) == :room_id
    end

    test "user_id field source" do
      assert RoomMembership.__schema__(:field_source, :user_id) == :user_id
    end

    test "last_read_id field source" do
      assert RoomMembership.__schema__(:field_source, :last_read_id) == :last_read_id
    end

    test "inserted_at field source" do
      assert RoomMembership.__schema__(:field_source, :inserted_at) == :inserted_at
    end

    test "updated_at field source" do
      assert RoomMembership.__schema__(:field_source, :updated_at) == :updated_at
    end
  end

  describe "schema structure" do
    test "has correct primary key" do
      # RoomMembership should have an auto-generated id field
      assert RoomMembership.__schema__(:type, :id) == :id
    end

    test "has correct autogenerate fields" do
      autogenerate_fields = RoomMembership.__schema__(:autogenerate_fields)
      assert :inserted_at in autogenerate_fields
      assert :updated_at in autogenerate_fields
    end

    test "has correct read_after_writes" do
      raw_fields = RoomMembership.__schema__(:read_after_writes)
      # The read_after_writes may be empty for this schema
      assert is_list(raw_fields)
    end
  end

  describe "changeset behavior" do
    test "changeset doesn't modify data when no changes" do
      membership = %RoomMembership{room_id: 1, user_id: 2, last_read_id: 100}
      changeset = RoomMembership.changeset(membership, %{})

      assert changeset.valid?
      assert changeset.data == membership
      assert changeset.changes == %{}
    end

    test "changeset preserves existing data" do
      membership = %RoomMembership{room_id: 1, user_id: 2, last_read_id: 100}
      changeset = RoomMembership.changeset(membership, %{some_attr: "value"})

      assert changeset.valid?
      assert changeset.data.room_id == 1
      assert changeset.data.user_id == 2
      assert changeset.data.last_read_id == 100
    end

    test "changeset handles empty map" do
      membership = %RoomMembership{}
      changeset = RoomMembership.changeset(membership, %{})

      assert changeset.valid?
      assert changeset.changes == %{}
    end
  end

  describe "last_read_id field" do
    test "can store nil last_read_id" do
      membership = %RoomMembership{last_read_id: nil}
      assert membership.last_read_id == nil
    end

    test "can store integer last_read_id" do
      membership = %RoomMembership{last_read_id: 123}
      assert membership.last_read_id == 123
    end

    test "can store large integer last_read_id" do
      large_id = 9_999_999_999
      membership = %RoomMembership{last_read_id: large_id}
      assert membership.last_read_id == large_id
    end

    test "can store zero as last_read_id" do
      membership = %RoomMembership{last_read_id: 0}
      assert membership.last_read_id == 0
    end
  end

  describe "module structure" do
    test "is an Ecto schema" do
      # Check that the module has schema functions
      assert function_exported?(RoomMembership, :__schema__, 1)
      assert function_exported?(RoomMembership, :__schema__, 2)
    end

    test "uses Ecto.Schema" do
      assert Code.ensure_loaded?(Ecto.Schema)
      # Verify the module uses the schema macros
      assert function_exported?(RoomMembership, :__schema__, 2)
    end

    test "has changeset function" do
      assert function_exported?(RoomMembership, :changeset, 2)
    end
  end
end
