defmodule Slap.UploadsTest do
  use Slap.DataCase, async: false

  alias Slap.Uploads

  setup do
    # Clean up any test files before and after tests
    on_exit(fn ->
      # Clean up test upload directory
      upload_dir = "priv/static/uploads"
      if File.exists?(upload_dir) do
        File.rm_rf!(upload_dir)
      end
    end)

    :ok
  end

  describe "upload_path_prefix/0" do
    test "returns the correct upload path prefix" do
      assert Uploads.upload_path_prefix() == "/uploads"
    end
  end

  describe "upload_file/1" do
    test "uploads a file successfully" do
      # Create a temporary file
      temp_path = Path.join(System.tmp_dir!(), "test_upload.txt")
      File.write!(temp_path, "test content")

      # Create a Plug.Upload struct
      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.txt",
        content_type: "text/plain"
      }

      # Upload the file
      result = Uploads.upload_file(upload)

      # Should return a path starting with /uploads
      assert String.starts_with?(result, "/uploads/")

      # Should contain a unique ID
      assert String.contains?(result, "-test.txt")

      # File should exist in the upload directory
      filename = Path.basename(result)
      upload_path = Path.join("priv/static/uploads", filename)
      assert File.exists?(upload_path)

      # Content should match
      assert File.read!(upload_path) == "test content"

      # Clean up
      File.rm!(temp_path)
    end

    test "generates unique filenames for same filename" do
      # Create two temporary files with same name
      temp_path1 = Path.join(System.tmp_dir!(), "test1.txt")
      temp_path2 = Path.join(System.tmp_dir!(), "test2.txt")
      File.write!(temp_path1, "content 1")
      File.write!(temp_path2, "content 2")

      upload1 = %Plug.Upload{path: temp_path1, filename: "same.txt"}
      upload2 = %Plug.Upload{path: temp_path2, filename: "same.txt"}

      result1 = Uploads.upload_file(upload1)
      result2 = Uploads.upload_file(upload2)

      # Results should be different
      assert result1 != result2

      # Both should contain the filename
      assert String.contains?(result1, "same.txt")
      assert String.contains?(result2, "same.txt")

      # But with different prefixes
      refute String.replace(result1, "same.txt", "") == String.replace(result2, "same.txt", "")

      # Clean up
      File.rm!(temp_path1)
      File.rm!(temp_path2)
    end

    test "creates upload directory if it doesn't exist" do
      # Remove upload directory if it exists
      upload_dir = "priv/static/uploads"
      if File.exists?(upload_dir) do
        File.rm_rf!(upload_dir)
      end

      # Create and upload a file
      temp_path = Path.join(System.tmp_dir!(), "test.txt")
      File.write!(temp_path, "test")

      upload = %Plug.Upload{path: temp_path, filename: "test.txt"}
      Uploads.upload_file(upload)

      # Directory should be created
      assert File.exists?(upload_dir)

      File.rm!(temp_path)
    end
  end

  describe "delete_file/1" do
    test "deletes an existing file" do
      # First upload a file
      temp_path = Path.join(System.tmp_dir!(), "delete_test.txt")
      File.write!(temp_path, "delete me")

      upload = %Plug.Upload{path: temp_path, filename: "delete_test.txt"}
      file_path = Uploads.upload_file(upload)

      # File should exist
      filename = Path.basename(file_path)
      full_path = Path.join("priv/static/uploads", filename)
      assert File.exists?(full_path)

      # Delete the file
      assert Uploads.delete_file(file_path) == :ok

      # File should be gone
      refute File.exists?(full_path)

      File.rm!(temp_path)
    end

    test "returns error for non-existent file" do
      result = Uploads.delete_file("/uploads/nonexistent.txt")
      assert result == {:error, :not_found}
    end

    test "handles files with full paths" do
      # First upload a file
      temp_path = Path.join(System.tmp_dir!(), "full_path_test.txt")
      File.write!(temp_path, "full path test")

      upload = %Plug.Upload{path: temp_path, filename: "full_path_test.txt"}
      file_path = Uploads.upload_file(upload)

      # Delete using the returned path
      assert Uploads.delete_file(file_path) == :ok

      File.rm!(temp_path)
    end
  end
end
