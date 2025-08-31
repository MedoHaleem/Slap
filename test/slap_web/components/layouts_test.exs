defmodule SlapWeb.LayoutsTest do
  use SlapWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders app layout" do
    html =
      render_to_string(SlapWeb.Layouts, "app", "html",
        flash: %{},
        inner_content: "<p>Test content</p>"
      )

    assert html =~ "flex w-full h-screen"
    assert html =~ "Test content"
    assert html =~ "flash-group"
  end

  test "renders root layout" do
    html =
      render_to_string(SlapWeb.Layouts, "root", "html", inner_content: "<div>Page content</div>")

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "lang=\"en\""
    assert html =~ "Page content"
    assert html =~ "csrf-token"
    assert html =~ "/assets/app.css"
    assert html =~ "/assets/app.js"
  end

  test "root layout includes page title" do
    html =
      render_to_string(SlapWeb.Layouts, "root", "html",
        inner_content: "<div>Content</div>",
        page_title: "Test Page"
      )

    assert html =~ "Test Page"
    assert html =~ "Slap"
  end
end
