defmodule SlapWeb.ChatRoomLive.ProfileComponent do
  use SlapWeb, :live_component

  alias Slap.Accounts
  import SlapWeb.UserComponents

  def mount(socket) do
    socket
    |> allow_upload(:avatar,
      accept: ~w(.png .jpeg .jpg),
      max_entries: 1,
      max_file_size: 2 * 1024 * 1024
    )
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col shrink-0 w-1/4 max-w-xs bg-white shadow-xl">
      <div class="flex items-center h-16 border-b border-slate-300 px-4">
        <div class="">
          <h2 class="text-lg font-bold text-gray-800">
            Profile
          </h2>
        </div>

        <button
          class="flex items-center justify-center w-6 h-6 rounded hover:bg-gray-300 ml-auto"
          phx-click="close-profile"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <div class="flex flex-col grow overflow-auto p-4">
        <div class="mb-4">
          <%= if @current_user.id == @user.id do %>
            <.form
              for={%{}}
              phx-change="validate-avatar"
              phx-target={@myself}
              phx-submit="submit-avatar"
            >
              <div class="mb-4">
                <%= if Enum.any?(@uploads.avatar.entries) do %>
                  <div class="mx-auto mb-2 w-48">
                    <.live_img_preview
                      entry={List.first(@uploads.avatar.entries)}
                      class="rounded"
                      width={192}
                      height={192}
                    />
                    <button
                      class="w-full bg-emerald-600 hover:bg-emerald-700 text-white rounded mt-2 py-1 shadow"
                      type="submit"
                    >
                      Save
                    </button>
                  </div>
                <% else %>
                  <.user_avatar user={@user} />
                <% end %>
              </div>

              <label class="block mb-2 font-semibold text-lg text-gray-800">
                Upload avatar
              </label>
               <.live_file_input upload={@uploads.avatar} class="w-full" />
            </.form>
             <hr class="mt-4" />
          <% else %>
            <.user_avatar user={@user} class="w-48 rounded mx-auto" />
          <% end %>
        </div>

        <h2 class="text-xl font-bold text-gray-800">
          {@user.username}
        </h2>
      </div>
    </div>
    """
  end

  def handle_event("submit-avatar", _, socket) do
    if socket.assigns.user.id != socket.assigns.current_user.id do
      raise "Prohibited"
    end

    avatar_path =
      socket
      |> consume_uploaded_entries(:avatar, fn %{path: path}, entry ->
        # Ensure uploads directory exists
        uploads_dir = "priv/static/uploads"
        File.mkdir_p!(uploads_dir)

        # Generate a unique filename preserving the original extension
        original_ext = Path.extname(entry.client_name)
        unique_filename = "#{generate_unique_id()}#{original_ext}"
        dest = Path.join(uploads_dir, unique_filename)

        File.cp!(path, dest)
        {:ok, unique_filename}
      end)
      |> List.first()

    {:ok, _user} = Accounts.save_user_avatar_path(socket.assigns.current_user, avatar_path)

    socket |> noreply()
  end

  def handle_event("validate-avatar", _, socket), do: {:noreply, socket}

  defp generate_unique_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
