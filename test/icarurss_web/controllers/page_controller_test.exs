defmodule IcarurssWeb.PageControllerTest do
  use IcarurssWeb.ConnCase

  test "GET / redirects unauthenticated users to log in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
