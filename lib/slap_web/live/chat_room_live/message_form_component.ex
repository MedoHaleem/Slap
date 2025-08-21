defmodule SlapWeb.ChatRoomLive.MessageFormComponent do
  use SlapWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, pdf_file: nil, show_file_selector: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-auto bg-white px-4 pb-4">
      <.form
        id="new-message-form"
        for={@form}
        phx-change="validate-message"
        phx-submit="submit-message"
        phx-target={@myself}
        multipart={true}
        class="flex flex-col border-2 border-slate-300 rounded-sm p-1"
      >
        <div class="flex items-center">
          <textarea
            class="grow text-sm px-3 border-l border-slate-300 mx-1 resize-none"
            cols=""
            id="chat-message-textarea"
            name={@form[:body].name}
            placeholder={"Message ##{@room.name}"}
            phx-debounce
            phx-hook="ChatMessageTextArea"
            rows="1"
          >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
          <div class="flex items-center">
            <button
              type="button"
              phx-click="toggle-file-selector"
              phx-target={@myself}
              class="shrink flex items-center justify-center h-6 w-6 rounded hover:bg-slate-200 mr-1"
              title="Attach PDF"
            >
              <.icon name="hero-paper-clip" class="h-4 w-4" />
            </button>
            
            <button
              type="submit"
              class="shrink flex items-center justify-center h-6 w-6 rounded hover:bg-slate-200"
            >
              <.icon name="hero-paper-airplane" class="h-4 w-4" />
            </button>
          </div>
        </div>
        
        <div :if={@show_file_selector} class="mt-2 p-2 border border-slate-200 rounded bg-slate-50">
          <div class="flex flex-col">
            <label class="text-sm text-slate-700 mb-1">Attach PDF file</label>
            <.live_file_input upload={@uploads.pdf_file} class="text-sm" />
            <div :if={@uploads.pdf_file.errors != []} class="mt-1 text-xs text-red-500">
              <span :for={{error, _} <- @uploads.pdf_file.errors}>
                {error_to_string(error)}
              </span>
            </div>
            
            <div
              :for={entry <- @uploads.pdf_file.entries}
              class="mt-2 flex items-center justify-between"
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-document" class="h-4 w-4 text-red-600" />
                <span class="text-xs truncate max-w-[150px]">{entry.client_name}</span>
                <span class="text-xs text-slate-500">{format_bytes(entry.client_size)}</span>
              </div>
              
              <button
                type="button"
                phx-click="cancel-upload"
                phx-target={@myself}
                phx-value-ref={entry.ref}
                class="text-xs text-red-500 hover:text-red-700"
              >
                &times;
              </button>
            </div>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> allow_upload(:pdf_file,
        accept: ~w(.pdf),
        max_entries: 1,
        # 10 MB
        max_file_size: 10_240_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate-message", %{"message" => message_params}, socket) do
    changeset = Slap.Chat.change_message(%Slap.Chat.Message{}, message_params)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit-message", %{"message" => message_params}, socket) do
    %{current_user: current_user, room: room} = socket.assigns

    # Process uploads
    {message_params, socket} = process_file_uploads(message_params, socket)

    # Don't submit empty messages with no attachments
    if String.trim(message_params["body"] || "") == "" && !has_attachments?(socket) do
      {:noreply, socket}
    else
      case Slap.Chat.create_message(room, message_params, current_user) do
        {:ok, _message} ->
          # Reset the form
          changeset = Slap.Chat.change_message(%Slap.Chat.Message{})

          socket =
            socket
            |> assign(form: to_form(changeset), show_file_selector: false)
            |> push_event("chat_message_submitted", %{})

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  @impl true
  def handle_event("toggle-file-selector", _, socket) do
    {:noreply, assign(socket, show_file_selector: !socket.assigns.show_file_selector)}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :pdf_file, ref)}
  end

  defp process_file_uploads(message_params, socket) do
    # Check if there are any uploaded files
    case uploaded_entries(socket, :pdf_file) do
      {[_entry], _} ->
        # Consume the upload immediately and get the upload
        upload =
          consume_uploaded_entries(socket, :pdf_file, fn %{path: path}, entry ->
            # Generate a unique filename
            unique_filename = "#{generate_unique_id()}-#{entry.client_name}"
            dest = Path.join("priv/static/uploads", unique_filename)

            # Copy the file to the uploads directory
            File.cp!(path, dest)

            # Create a Plug.Upload struct that Chat.create_message can use
            upload = %Plug.Upload{
              path: dest,
              filename: entry.client_name,
              content_type: entry.client_type
            }

            {:ok, upload}
          end)
          |> List.first()

        # Add the upload to message params
        {Map.put(message_params, "pdf_file", upload), socket}

      _ ->
        {message_params, socket}
    end
  end

  defp generate_unique_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp has_attachments?(socket) do
    uploads = socket.assigns.uploads

    if uploads && uploads.pdf_file do
      Enum.any?(uploads.pdf_file.entries)
    else
      false
    end
  end

  defp error_to_string(:too_large), do: "File is too large. Maximum size is 10MB."
  defp error_to_string(:not_accepted), do: "Only PDF files are accepted."
  defp error_to_string(:too_many_files), do: "You can only upload one file at a time."
  defp error_to_string(_), do: "Invalid file upload."

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} bytes"
    end
  end
end
