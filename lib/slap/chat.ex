defmodule Slap.Chat do
  alias Slap.Chat.Room
  alias Slap.Repo

  def list_rooms do
    Repo.all(Room)
  end
end
