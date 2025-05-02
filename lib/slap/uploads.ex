defmodule Slap.Uploads do
  @upload_directory "priv/static/uploads"
  @upload_path_prefix "/uploads"

  def upload_path_prefix, do: @upload_path_prefix

  def upload_file(%Plug.Upload{path: temp_path, filename: filename}) do
    # Ensure upload directory exists
    File.mkdir_p!(@upload_directory)

    # Generate unique filename to prevent collisions
    unique_filename = "#{generate_unique_id()}-#{filename}"
    file_path = Path.join(@upload_directory, unique_filename)

    # Copy the file
    File.cp!(temp_path, file_path)

    # Return the public path to the file
    Path.join(@upload_path_prefix, unique_filename)
  end

  def delete_file(file_path) do
    # Extract the filename from the path
    filename = Path.basename(file_path)

    # Construct the full path to the file in the upload directory
    full_path = Path.join(@upload_directory, filename)

    # Delete the file if it exists
    if File.exists?(full_path) do
      File.rm!(full_path)
      :ok
    else
      {:error, :not_found}
    end
  end

  defp generate_unique_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
