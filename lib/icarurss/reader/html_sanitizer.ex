defmodule Icarurss.Reader.HtmlSanitizer do
  @moduledoc false

  def sanitize_fragment(nil), do: nil

  def sanitize_fragment(html) when is_binary(html) do
    html
    |> HtmlSanitizeEx.basic_html()
    |> String.trim()
    |> blank_to_nil()
  end

  def sanitize_fragment(_other), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
