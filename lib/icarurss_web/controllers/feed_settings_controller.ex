defmodule IcarurssWeb.FeedSettingsController do
  use IcarurssWeb, :controller

  alias Icarurss.Reader

  def export_opml(conn, _params) do
    user = conn.assigns.current_scope.user
    {:ok, opml_xml} = Reader.export_opml_for_user(user)
    filename = "icarurss-feeds-#{Date.utc_today()}.opml"

    send_download(conn, {:binary, opml_xml},
      filename: filename,
      content_type: "text/x-opml"
    )
  end

  def import_opml(conn, %{"import_opml" => %{"opml" => %Plug.Upload{path: path}}}) do
    user = conn.assigns.current_scope.user

    with {:ok, opml_xml} <- File.read(path),
         {:ok, stats} <- Reader.import_opml_for_user(user, opml_xml) do
      message =
        "Import complete: #{stats.feeds_added} feeds added, #{stats.feeds_skipped} skipped, #{stats.folders_created} folders created."

      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/users/settings/opml")
    else
      _ ->
        conn
        |> put_flash(:error, "Could not import OPML file.")
        |> redirect(to: ~p"/users/settings/opml")
    end
  end

  def import_opml(conn, _params) do
    conn
    |> put_flash(:error, "Please choose an OPML file to import.")
    |> redirect(to: ~p"/users/settings/opml")
  end
end
