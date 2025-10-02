# File Upload System

This document provides a comprehensive overview of the file upload functionality in Slap, including file validation, storage, and security considerations.

## Overview

The file upload system allows users to:

- Upload files with messages in chat rooms
- Upload files with direct messages
- View and download shared files
- Manage file attachments
- Validate file types and sizes

## Architecture

### Context Module

File upload logic is handled by the [`Slap.Uploads`](../../lib/slap/uploads.ex) context module, which provides:

- File validation and processing
- Secure file storage
- File deletion
- Path management

### Schema Module

File attachment data is stored using the [`Slap.Chat.MessageAttachment`](../../lib/slap/chat/message_attachment.ex) schema.

### Integration

File uploads are integrated with:

- Chat room messages
- Direct messages
- User avatars (handled separately in accounts)

## Supported File Types

### Current Support

- **PDF files**: `.pdf` (up to 10MB)
- **Images**: `.jpg`, `.jpeg`, `.png`, `.gif` (up to 5MB)
- **Documents**: `.txt`, `.doc`, `.docx` (up to 5MB)

### File Type Validation

```elixir
def validate_file_type(upload) do
  allowed_types = [
    "application/pdf",
    "image/jpeg",
    "image/png", 
    "image/gif",
    "text/plain",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  ]
  
  if upload.content_type in allowed_types do
    :ok
  else
    {:error, :invalid_file_type}
  end
end
```

### File Size Limits

```elixir
def validate_file_size(upload, max_size \\ 10_485_760) do
  # Default max size: 10MB
  file_size = upload.path |> File.stat!() |> Map.get(:size)
  
  if file_size <= max_size do
    :ok
  else
    {:error, :file_too_large}
  end
end
```

## Upload Process

### Step-by-Step Flow

1. **File Selection**: User selects files through the file input
2. **Client Validation**: Basic validation on the client side
3. **Upload Request**: Files are uploaded to the server
4. **Server Validation**: Comprehensive validation of file type and size
5. **File Processing**: Files are processed and stored securely
6. **Database Record**: Attachment records are created in the database
7. **Association**: Files are associated with messages

### Upload Implementation

```elixir
defmodule Slap.Uploads do
  @upload_dir "priv/static/uploads"
  
  def upload_file(%Plug.Upload{path: temp_path, filename: filename}) do
    # Validate file
    with {:ok, upload} <- validate_upload(%Plug.Upload{path: temp_path, filename: filename}),
         unique_filename <- generate_unique_filename(filename),
         upload_path <- Path.join(@upload_dir, unique_filename),
         :ok <- File.cp(temp_path, upload_path) do
      {:ok, "/uploads/" <> unique_filename}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_upload(upload) do
    with :ok <- validate_file_type(upload),
         :ok <- validate_file_size(upload) do
      {:ok, upload}
    else
      error -> error
    end
  end
  
  defp generate_unique_filename(filename) do
    extension = Path.extname(filename)
    base_name = Path.basename(filename, extension)
    timestamp = :os.system_time(:millisecond)
    "#{base_name}_#{timestamp}#{extension}"
  end
end
```

## File Storage

### Storage Location

Files are stored in the `priv/static/uploads/` directory:

```
priv/static/uploads/
├── documents/
├── images/
└── pdfs/
```

### Directory Structure

```elixir
def get_upload_path(filename, content_type) do
  directory = 
    cond do
      String.starts_with?(content_type, "image/") -> "images"
      content_type == "application/pdf" -> "pdfs"
      true -> "documents"
    end
  
  upload_dir = Path.join(@upload_dir, directory)
  File.mkdir_p!(upload_dir)
  
  Path.join(upload_dir, filename)
end
```

### File Naming

Files are renamed to prevent conflicts:

```elixir
def generate_unique_filename(original_filename) do
  extension = Path.extname(original_filename)
  base_name = Path.basename(original_filename, extension)
  
  # Create a unique identifier
  timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  random_string = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  
  "#{base_name}_#{timestamp}_#{random_string}#{extension}"
end
```

## Message Attachments

### Creating Attachments

```elixir
def create_message_attachment(message, upload) do
  case Slap.Uploads.upload_file(upload) do
    {:ok, file_path} ->
      %MessageAttachment{}
      |> MessageAttachment.changeset(%{
        filename: upload.filename,
        path: file_path,
        content_type: upload.content_type,
        size: get_file_size(upload)
      })
      |> Ecto.Changeset.put_assoc(:message, message)
      |> Repo.insert()
    
    {:error, reason} ->
      {:error, reason}
  end
end
```

### Attachment Schema

```elixir
defmodule Slap.Chat.MessageAttachment do
  use Ecto.Schema
  import Ecto.Changeset
  
  schema "message_attachments" do
    field :filename, :string
    field :path, :string
    field :content_type, :string
    field :size, :integer
    
    belongs_to :message, Slap.Chat.Message
    belongs_to :direct_message, Slap.Chat.DirectMessage
    
    timestamps()
  end
  
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :path, :content_type, :size])
    |> validate_required([:filename, :path, :content_type, :size])
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_length(:path, min: 1, max: 500)
  end
end
```

## LiveView Integration

### Upload Form Component

```elixir
defmodule SlapWeb.ChatRoomLive.MessageFormComponent do
  use Phoenix.LiveComponent
  
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:uploads, %{
        avatar: allowed_upload(:files, 
          accept: ~w(.pdf .jpg .jpeg .png .gif .txt .doc .docx),
          max_file_size: 10_485_760, # 10MB
          max_entries: 5
        )
      })
    
    {:ok, socket}
  end
  
  def handle_event("validate-message", %{"message" => message_params}, socket) do
    changeset =
      %Message{}
      |> Message.changeset(message_params)
      |> Map.put(:action, :validate)
    
    {:noreply, assign(socket, changeset: changeset)}
  end
  
  def handle_event("submit-message", %{"message" => message_params}, socket) do
    # Handle message submission with file uploads
    case consume_uploaded_entries(socket, :files, &upload_file/2) do
      {:ok, file_paths} ->
        # Create message with attachments
        create_message_with_attachments(socket, message_params, file_paths)
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "File upload failed: #{reason}")}
    end
  end
  
  defp upload_file(%Plug.Upload{} = upload, entry) do
    case Slap.Uploads.upload_file(upload) do
      {:ok, path} -> {:ok, path}
      {:error, _reason} -> {:error, :upload_failed}
    end
  end
end
```

### Upload Progress

```elixir
def render(assigns) do
  ~H"""
  <form phx-change="validate-message" phx-submit="submit-message">
    <.input
      type="textarea"
      name="message[body]"
      value={@changeset |> Ecto.Changeset.get_field(:body)}
      placeholder="Type your message..."
    />
    
    <div class="mt-2">
      <.live_file_input upload={@uploads.files} />
      
      <%= for entry <- @uploads.files.entries do %>
        <div class="mt-2 p-2 border rounded">
          <div><%= entry.client_name %></div>
          <div class="text-sm text-gray-500">
            <%= entry.progress %>%
            <%= if entry.progress == 100 do %>
              - Uploaded
            <% else %>
              - Uploading...
            <% end %>
          </div>
          
          <%= if entry.progress < 100 do %>
            <progress value={entry.progress} max="100" class="w-full" />
          <% end %>
          
          <button
            type="button"
            phx-click="cancel-upload"
            phx-value-ref={entry.ref}
            phx-target={@myself}
            class="text-red-500 text-sm"
          >
            Cancel
          </button>
        </div>
      <% end %>
    </div>
    
    <.button type="submit" phx-disable-with="Sending...">
      Send Message
    </.button>
  </form>
  """
end
```

## File Display

### Message Component with Attachments

```elixir
defmodule SlapWeb.ChatComponents do
  def message(assigns) do
    ~H"""
    <div class="message-container">
      <div class="message-header">
        <img src={@message.user.avatar_path || "/images/profile_avatar.png"} 
             class="w-8 h-8 rounded-full" />
        <span class="font-semibold"><%= @message.user.username %></span>
        <span class="text-gray-500 text-sm">
          <%= message_timestamp(@message, @timezone) %>
        </span>
      </div>
      
      <div class="message-body mt-2">
        <p><%= @message.body %></p>
        
        <%= if @message.attachments && @message.attachments != [] do %>
          <div class="attachments mt-3">
            <h4 class="text-sm font-semibold mb-2">Attachments:</h4>
            <div class="space-y-2">
              <%= for attachment <- @message.attachments do %>
                <.attachment_display attachment={attachment} />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
  
  def attachment_display(assigns) do
    ~H"""
    <div class="flex items-center space-x-2 p-2 bg-gray-100 rounded">
      <div class="attachment-icon">
        <%= attachment_icon(@attachment.content_type) %>
      </div>
      
      <div class="flex-1">
        <div class="font-medium text-sm"><%= @attachment.filename %></div>
        <div class="text-xs text-gray-500">
          <%= format_file_size(@attachment.size) %>
        </div>
      </div>
      
      <a href={@attachment.path} 
         download={@attachment.filename}
         class="text-blue-500 hover:text-blue-700">
        Download
      </a>
    </div>
    """
  end
  
  defp attachment_icon(content_type) do
    case content_type do
      "application/pdf" -> 
        ~H|<span class="text-red-500">📄</span>|
      "image/" <> _ -> 
        ~H|<span class="text-green-500">🖼️</span>|
      "text/plain" -> 
        ~H|<span class="text-blue-500">📝</span>|
      _ -> 
        ~H|<span class="text-gray-500">📎</span>|
    end
  end
  
  defp format_file_size(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{Float.round(bytes / 1_048_576, 1)} MB"
    end
  end
end
```

## File Deletion

### Deleting Attachments

```elixir
def delete_message_attachment(attachment_id, %User{} = user) do
  attachment = Repo.get(MessageAttachment, attachment_id)
  
  cond do
    is_nil(attachment) ->
      {:error, :not_found}
    
    attachment.message.user_id != user.id ->
      {:error, :unauthorized}
    
    true ->
      Repo.transaction(fn ->
        # Delete file from storage
        File.rm(Path.join("priv/static", attachment.path))
        
        # Delete database record
        Repo.delete(attachment)
      end)
  end
end
```

### Cleanup on Message Deletion

```elixir
def delete_message(%Message{} = message) do
  Repo.transaction(fn ->
    # Delete associated files
    Enum.each(message.attachments, fn attachment ->
      File.rm(Path.join("priv/static", attachment.path))
    end)
    
    # Delete message (cascades to attachments)
    Repo.delete(message)
  end)
end
```

## Security Considerations

### File Type Validation

- Whitelist approach for allowed file types
- Content-type verification
- File extension validation
- Magic number verification (future enhancement)

### Path Traversal Prevention

```elixir
def secure_file_path(filename) do
  # Remove any path traversal attempts
  safe_filename = String.replace(filename, "..", "")
  
  # Ensure the file stays within the upload directory
  Path.join(@upload_dir, safe_filename)
  |> Path.expand()
  |> String.starts_with?(Path.expand(@upload_dir))
  |> case do
    true -> Path.join(@upload_dir, safe_filename)
    false -> raise "Path traversal attempt detected"
  end
end
```

### Access Control

- Files served through static file handler
- No direct file system access
- Authentication required for file access
- Authorization checks for file ownership

### Virus Scanning (Future)

```elixir
def scan_for_malware(file_path) do
  # Integration with antivirus scanning service
  case Clamex.scan(file_path) do
    {:ok, :clean} -> :ok
    {:ok, {:virus, virus_name}} -> {:error, {:virus_detected, virus_name}}
    {:error, reason} -> {:error, {:scan_failed, reason}}
  end
end
```

## Performance Considerations

### File Size Limits

- Configurable size limits per file type
- Total upload size per message
- User quota limits (future)

### Storage Management

```elixir
def cleanup_old_files(days_old \\ 30) do
  cutoff_date = DateTime.add(DateTime.utc_now(), -days_old * 24 * 60 * 60, :second)
  
  from(a in MessageAttachment, 
    where: a.inserted_at < ^cutoff_date)
  |> Repo.all()
  |> Enum.each(fn attachment ->
    # Delete file and database record
    File.rm(Path.join("priv/static", attachment.path))
    Repo.delete(attachment)
  end)
end
```

### CDN Integration (Future)

```elixir
def upload_to_cdn(local_path, filename) do
  # Integration with CDN service (AWS S3, CloudFront, etc.)
  case ExAws.S3.put_object("slap-uploads", filename, File.read!(local_path)) do
    {:ok, _result} -> {:ok, cdn_url(filename)}
    {:error, reason} -> {:error, reason}
  end
end
```

## Error Handling

### Common Error Scenarios

1. **File Too Large**: User tries to upload a file exceeding size limits
2. **Invalid File Type**: User tries to upload an unsupported file type
3. **Upload Failed**: Network or server issues during upload
4. **Storage Full**: Server storage space exhausted
5. **Permission Denied**: File system permission issues

### Error Messages

```elixir
defp upload_error_message(:file_too_large), do: "File size exceeds maximum allowed size"
defp upload_error_message(:invalid_file_type), do: "File type not supported"
defp upload_error_message(:upload_failed), do: "Failed to upload file"
defp upload_error_message(:storage_full), do: "Storage space full"
defp upload_error_message(:permission_denied), do: "Permission denied"
defp upload_error_message(_), do: "Unknown error occurred"
```

## Testing

### Unit Tests

```elixir
defmodule Slap.UploadsTest do
  use Slap.DataCase
  
  test "uploads valid file successfully" do
    upload = %Plug.Upload{
      path: "test/fixtures/sample.pdf",
      filename: "sample.pdf",
      content_type: "application/pdf"
    }
    
    assert {:ok, path} = Slap.Uploads.upload_file(upload)
    assert String.starts_with?(path, "/uploads/")
  end
  
  test "rejects invalid file type" do
    upload = %Plug.Upload{
      path: "test/fixtures/sample.exe",
      filename: "sample.exe",
      content_type: "application/octet-stream"
    }
    
    assert {:error, :invalid_file_type} = Slap.Uploads.upload_file(upload)
  end
end
```

### Integration Tests

```elixir
defmodule SlapWeb.ChatRoomLiveTest do
  use SlapWeb.ConnCase
  
  test "uploads file with message", %{conn: conn} do
    user = user_fixture()
    room = room_fixture()
    
    {:ok, view, _html} = live(conn, "/rooms/#{room.id}")
    
    file_input(view, "form", :files, [
      %{
        name: "test.pdf",
        content: "fake pdf content",
        type: "application/pdf"
      }
    ])
    
    render_submit(view, "submit-message", message: %{body: "Test message"})
    
    assert render(view) =~ "test.pdf"
    assert render(view) =~ "Test message"
  end
end
```

## Future Enhancements

### Planned Features

- Image preview and thumbnails
- Video file support
- File compression
- Virus scanning integration
- CDN storage integration
- File versioning
- Collaborative document editing
- File sharing permissions

### Technical Improvements

- Streaming uploads for large files
- Chunked upload support
- Resume interrupted uploads
- File deduplication
- Storage analytics
- Automatic file conversion

This file upload system provides a secure and efficient way for users to share files within the chat application while maintaining proper security and performance considerations.