defmodule Slap.Chat do
  alias Slap.Chat.Room
  alias Slap.Repo
  import Ecto.Query

  def change_room(room, attrs \\ %{}) do
    Room.changeset(room, attrs)
  end

  def list_rooms do
    Repo.all(from Room, order_by: [asc: :name])
  end

  def get_room!(id) do
    Repo.get!(Room, id)
  end

  def create_room(attrs) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end
end
