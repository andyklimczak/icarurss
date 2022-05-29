defmodule IcarurssWeb.PageController do
  use IcarurssWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
