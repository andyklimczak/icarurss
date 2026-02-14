defmodule IcarurssWeb.PageController do
  use IcarurssWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
