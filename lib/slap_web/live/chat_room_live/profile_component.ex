defmodule SlapWeb.ChatRoomLive.ProfileComponent do
  use SlapWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="flex flex-col shrink-0 w-1/4 max-w-xs bg-white shadow-xl">
      <div class="flex items-center h-16 border-b border-slate-300 px-4">
        <div class="">
          <h2 class="text-lg font-bold text-gray-800">
            Profile
          </h2>
        </div>
      </div>
      <div class="flex flex-col grow overflow-auto p-4">
        <div class="mb-4">
          <img src={~p"/images/one_ring.jpg"} class="w-48 rounded mx-auto" />
        </div>
        <h2 class="text-xl font-bold text-gray-800">
          {@user.username}
        </h2>
      </div>
    </div>
    """
  end
end
