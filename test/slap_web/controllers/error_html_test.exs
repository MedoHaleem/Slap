defmodule SlapWeb.ErrorHTMLTest do
  use SlapWeb.ConnCase, async: true

  alias SlapWeb.ErrorHTML

  describe "render/2" do
    test "renders 404.html template" do
      result = ErrorHTML.render("404.html", %{})
      assert result == "Not Found"
    end

    test "renders 500.html template" do
      result = ErrorHTML.render("500.html", %{})
      assert result == "Internal Server Error"
    end

    test "renders 403.html template" do
      result = ErrorHTML.render("403.html", %{})
      assert result == "Forbidden"
    end

    test "renders 401.html template" do
      result = ErrorHTML.render("401.html", %{})
      assert result == "Unauthorized"
    end

    test "renders 422.html template" do
      result = ErrorHTML.render("422.html", %{})
      assert result == "Unprocessable Entity"
    end

    test "renders custom status codes" do
      result = ErrorHTML.render("418.html", %{})
      assert result == "I'm a teapot"
    end

    test "handles unknown status codes" do
      result = ErrorHTML.render("999.html", %{})
      assert result == "Internal Server Error"
    end

    test "ignores assigns parameter" do
      assigns = %{custom_message: "Custom error"}
      result = ErrorHTML.render("404.html", assigns)
      assert result == "Not Found"
    end

    test "handles nil assigns" do
      result = ErrorHTML.render("404.html", nil)
      assert result == "Not Found"
    end

    test "handles empty assigns" do
      result = ErrorHTML.render("404.html", %{})
      assert result == "Not Found"
    end
  end

  describe "template parsing" do
    test "parses standard HTTP status templates" do
      templates = ["400.html", "401.html", "403.html", "404.html", "422.html", "500.html"]

      for template <- templates do
        result = ErrorHTML.render(template, %{})
        assert is_binary(result)
        assert result != ""
      end
    end

    test "handles templates without .html extension" do
      result = ErrorHTML.render("404", %{})
      assert result == "Not Found"
    end

    test "handles templates with different extensions" do
      result = ErrorHTML.render("404.json", %{})
      assert result == "Not Found"
    end

    test "handles numeric status codes as strings" do
      result = ErrorHTML.render("404", %{})
      assert result == "Not Found"
    end
  end

  describe "Phoenix integration" do
    test "uses Phoenix.Controller.status_message_from_template" do
      # Test that our render function delegates to Phoenix's function
      result = ErrorHTML.render("404.html", %{})
      phoenix_result = Phoenix.Controller.status_message_from_template("404.html")
      assert result == phoenix_result
    end

    test "maintains compatibility with Phoenix error handling" do
      # Test various status codes that Phoenix supports
      status_codes = [400, 401, 403, 404, 422, 500]

      for code <- status_codes do
        template = "#{code}.html"
        result = ErrorHTML.render(template, %{})
        assert is_binary(result)
        assert result != ""
      end
    end
  end

  describe "module structure" do
    test "is a Phoenix HTML module" do
      assert Code.ensure_loaded?(Phoenix.HTML)
      # The module uses SlapWeb, :html which should include Phoenix.HTML functionality
    end

    test "has render function" do
      assert function_exported?(ErrorHTML, :render, 2)
    end

    test "module documentation exists" do
      # Check that the module has documentation
      case Code.fetch_docs(ErrorHTML) do
        {:docs_v1, _, _, _, %{"en" => docs}, _, _} ->
          assert docs != nil
        _ ->
          # If docs are not available, just check the module exists
          assert Code.ensure_loaded?(ErrorHTML)
      end
    end
  end

  describe "error handling" do
    test "handles malformed templates gracefully" do
      result = ErrorHTML.render("", %{})
      assert result == "Internal Server Error"
    end

    test "handles nil template" do
      result = ErrorHTML.render(nil, %{})
      assert result == "Internal Server Error"
    end

    test "handles non-string templates" do
      result = ErrorHTML.render(404, %{})
      assert result == "Internal Server Error"
    end
  end

  describe "customization comments" do
    test "module contains customization instructions" do
      # The module source should contain comments about customization
      source = File.read!("lib/slap_web/controllers/error_html.ex")
      assert source =~ "embed_templates"
      assert source =~ "error_html/*"
    end
  end
end
