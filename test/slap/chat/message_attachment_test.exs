defmodule Slap.Chat.MessageAttachmentTest do
  use Slap.DataCase, async: true

  alias Slap.Chat.MessageAttachment

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        file_path: "/uploads/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        message_id: 1
      }

      changeset = MessageAttachment.changeset(%MessageAttachment{}, attrs)
      assert changeset.valid?
      assert changeset.changes == attrs
    end

    test "invalid changeset missing required fields" do
      changeset = MessageAttachment.changeset(%MessageAttachment{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :file_path)
      assert Map.has_key?(errors, :file_name)
      assert Map.has_key?(errors, :file_type)
      assert Map.has_key?(errors, :file_size)
      assert Map.has_key?(errors, :base)
    end

    test "validates PDF file type" do
      attrs = %{
        file_path: "/uploads/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        message_id: 1
      }

      changeset = MessageAttachment.changeset(%MessageAttachment{}, attrs)
      assert changeset.valid?
    end

    test "rejects non-PDF file types" do
      attrs = %{
        file_path: "/uploads/test.jpg",
        file_name: "test.jpg",
        file_type: "image/jpeg",
        file_size: 1024,
        message_id: 1
      }

      changeset = MessageAttachment.changeset(%MessageAttachment{}, attrs)
      refute changeset.valid?
      assert %{file_type: ["Only PDF files are allowed"]} = errors_on(changeset)
    end

    test "validates foreign key constraint" do
      attrs = %{
        file_path: "/uploads/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        # Non-existent message ID
        message_id: 999
      }

      changeset = MessageAttachment.changeset(%MessageAttachment{}, attrs)
      # The foreign key constraint validation happens at the database level
      # So this should pass changeset validation but fail on insert
      assert changeset.valid?
    end
  end

  describe "upload_changeset/2" do
    test "valid upload changeset with PDF file" do
      # Create a temporary PDF file
      temp_path = Path.join(System.tmp_dir!(), "test_upload.pdf")
      File.write!(temp_path, "%PDF-1.5\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.pdf",
        content_type: "application/pdf"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :file_name) == "test.pdf"
      assert get_change(changeset, :file_type) == "application/pdf"
      assert get_change(changeset, :file_size) > 0

      # Clean up
      File.rm!(temp_path)
    end

    test "rejects non-PDF files in upload" do
      # Create a temporary non-PDF file
      temp_path = Path.join(System.tmp_dir!(), "test_upload.jpg")
      File.write!(temp_path, "fake image content")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      refute changeset.valid?
      assert %{file: ["Only PDF files are allowed"]} = errors_on(changeset)

      # Clean up
      File.rm!(temp_path)
    end

    test "handles missing file in upload changeset" do
      attrs = %{message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :file)
      assert "can't be blank" in errors.file
    end

    test "handles invalid file in upload changeset" do
      attrs = %{file: "not a plug upload", message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      refute changeset.valid?
      assert %{file: ["Invalid file"]} = errors_on(changeset)
    end

    test "handles non-existent file path" do
      upload = %Plug.Upload{
        path: "/non/existent/path/test.pdf",
        filename: "test.pdf",
        content_type: "application/pdf"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      assert changeset.valid?
      # File size should be 0 for non-existent files
      assert get_change(changeset, :file_size) == 0
    end

    test "validates message_id presence in upload changeset" do
      temp_path = Path.join(System.tmp_dir!(), "test.pdf")
      File.write!(temp_path, "%PDF content")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.pdf",
        content_type: "application/pdf"
      }

      attrs = %{file: upload}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      refute changeset.valid?
      assert %{base: ["Must belong to either message or direct message"]} = errors_on(changeset)

      File.rm!(temp_path)
    end
  end

  describe "file validation" do
    test "accepts PDF files with .pdf extension" do
      temp_path = Path.join(System.tmp_dir!(), "test.PDF")
      File.write!(temp_path, "%PDF content")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.PDF",
        content_type: "application/pdf"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      assert changeset.valid?

      File.rm!(temp_path)
    end

    test "accepts PDF files with .Pdf extension" do
      temp_path = Path.join(System.tmp_dir!(), "test.Pdf")
      File.write!(temp_path, "%PDF content")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.Pdf",
        content_type: "application/pdf"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      assert changeset.valid?

      File.rm!(temp_path)
    end

    test "accepts files with PDF extension regardless of content type" do
      temp_path = Path.join(System.tmp_dir!(), "test.pdf")
      File.write!(temp_path, "not pdf content")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "test.pdf",
        content_type: "text/plain"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      # The validation only checks file extension, not content type
      assert changeset.valid?
      assert get_change(changeset, :file_name) == "test.pdf"

      File.rm!(temp_path)
    end
  end

  describe "file size handling" do
    test "calculates file size correctly for existing files" do
      content = "This is test content for file size calculation"
      temp_path = Path.join(System.tmp_dir!(), "size_test.pdf")
      File.write!(temp_path, content)

      upload = %Plug.Upload{
        path: temp_path,
        filename: "size_test.pdf",
        content_type: "application/pdf"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :file_size) == byte_size(content)

      File.rm!(temp_path)
    end

    test "handles zero byte files" do
      temp_path = Path.join(System.tmp_dir!(), "empty.pdf")
      File.write!(temp_path, "")

      upload = %Plug.Upload{
        path: temp_path,
        filename: "empty.pdf",
        content_type: "application/pdf"
      }

      attrs = %{file: upload, message_id: 1}
      changeset = MessageAttachment.upload_changeset(%MessageAttachment{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :file_size) == 0

      File.rm!(temp_path)
    end
  end
end
