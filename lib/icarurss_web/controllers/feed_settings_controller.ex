defmodule IcarurssWeb.FeedSettingsController do
  use IcarurssWeb, :controller

  require Logger

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
        "Import complete: #{stats.feeds_added} feeds added, #{stats.feeds_skipped} skipped, #{stats.folders_created} folders created, #{format_refresh_queue_phrase(stats.refreshes_queued)}#{format_refresh_failure_suffix(stats.refreshes_failed)}."

      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/users/settings/opml")
    else
      {:error, reason} ->
        message = import_opml_error_message(reason)

        Logger.error("OPML import failed for user_id=#{user.id}: #{message}")

        conn
        |> put_flash(:error, "Could not import OPML file: #{message}.")
        |> redirect(to: ~p"/users/settings/opml")
    end
  end

  def import_opml(conn, _params) do
    conn
    |> put_flash(:error, "Please choose an OPML file to import.")
    |> redirect(to: ~p"/users/settings/opml")
  end

  def reset_opml_data(conn, _params) do
    if dev_opml_reset_enabled?() do
      user = conn.assigns.current_scope.user

      case Reader.delete_all_feeds_and_articles_for_user(user) do
        {:ok, stats} ->
          conn
          |> put_flash(
            :info,
            "Development reset complete: #{stats.feeds_deleted} feeds and #{stats.articles_deleted} articles deleted."
          )
          |> redirect(to: ~p"/users/settings/opml")

        {:error, reason} ->
          Logger.error("OPML development reset failed for user_id=#{user.id}: #{inspect(reason)}")

          conn
          |> put_flash(:error, "Could not reset feeds and articles.")
          |> redirect(to: ~p"/users/settings/opml")
      end
    else
      conn
      |> put_status(:not_found)
      |> text("Not Found")
    end
  end

  defp import_opml_error_message(reason) when is_binary(reason), do: reason

  defp import_opml_error_message(reason) when is_atom(reason) do
    reason
    |> :file.format_error()
    |> to_string()
  end

  defp import_opml_error_message(reason), do: inspect(reason)

  defp format_refresh_queue_phrase(1), do: "1 initial refresh queued"
  defp format_refresh_queue_phrase(count), do: "#{count} initial refreshes queued"

  defp format_refresh_failure_suffix(0), do: ""
  defp format_refresh_failure_suffix(count), do: ", #{count} refreshes failed to queue"

  defp dev_opml_reset_enabled?, do: Application.get_env(:icarurss, :dev_routes, false)
end
