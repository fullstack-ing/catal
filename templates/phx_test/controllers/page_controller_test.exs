defmodule <%= @web_namespace %>.PageControllerTest do
  use <%= @web_namespace %>.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Home Page"
  end
end
