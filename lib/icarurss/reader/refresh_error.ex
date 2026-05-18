defmodule Icarurss.Reader.RefreshError do
  @moduledoc """
  Classified feed refresh failure used to decide logging, persistence, and Oban retry behavior.
  """

  @enforce_keys [:kind, :message, :retryable?, :permanent?]
  defstruct [:kind, :message, :retryable?, :permanent?, meta: %{}]

  @type kind :: :request | :http_status | :non_feed | :parse | :too_large
  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          retryable?: boolean(),
          permanent?: boolean(),
          meta: map()
        }

  def new(kind, message, opts \\ []) when is_atom(kind) and is_binary(message) do
    retryable? = Keyword.get_lazy(opts, :retryable?, fn -> retryable_kind?(kind) end)

    %__MODULE__{
      kind: kind,
      message: message,
      retryable?: retryable?,
      permanent?: Keyword.get(opts, :permanent?, not retryable?),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def from(reason, meta \\ %{})

  def from(%__MODULE__{} = error, extra_meta) do
    %{error | meta: Map.merge(error.meta || %{}, extra_meta || %{})}
  end

  def from(reason, meta) do
    message = message(reason)
    kind = kind_from_message(message, meta)
    retryable? = retryable?(kind, meta)

    new(kind, message, retryable?: retryable?, permanent?: not retryable?, meta: meta)
  end

  def message(%__MODULE__{message: message}), do: message
  def message(reason) when is_binary(reason), do: reason
  def message(reason), do: inspect(reason)

  def retryable?(%__MODULE__{retryable?: retryable?}), do: retryable?
  def retryable?(_reason), do: true

  def retryable?(kind, meta) when is_atom(kind),
    do: retryable_kind?(kind) or transient_status?(meta)

  def permanent?(%__MODULE__{permanent?: permanent?}), do: permanent?
  def permanent?(reason), do: not retryable?(reason)

  defp kind_from_message(message, meta) do
    cond do
      Map.get(meta, :halted_reason) == :too_large or
          String.contains?(message, "exceeded max size") ->
        :too_large

      Map.get(meta, :halted_reason) == :non_feed or
          String.contains?(message, "valid RSS/Atom feed") ->
        :non_feed

      String.starts_with?(message, "Request failed with status") ->
        :http_status

      String.starts_with?(message, "Request error:") ->
        :request

      String.starts_with?(message, "Could not parse feed XML") ->
        :parse

      true ->
        :request
    end
  end

  defp retryable_kind?(:request), do: true
  defp retryable_kind?(:http_status), do: false
  defp retryable_kind?(_kind), do: false

  defp transient_status?(%{http_status: status}) when status in [408, 429, 500, 502, 503, 504],
    do: true

  defp transient_status?(_meta), do: false
end
