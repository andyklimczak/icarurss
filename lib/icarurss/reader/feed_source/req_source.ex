defmodule Icarurss.Reader.FeedSource.ReqSource do
  @moduledoc """
  Default feed source implementation backed by Req.
  """

  @behaviour Icarurss.Reader.FeedSource

  alias Icarurss.Reader.{FeedDiscovery, FeedParser}

  @user_agent "icarurss/0.1 (+self-hosted)"

  @impl true
  def discover(url_input) when is_binary(url_input) do
    with {:ok, normalized_url} <- normalize_url(url_input),
         {:ok, response} <- fetch(normalized_url) do
      body = response.body |> to_string()

      case FeedParser.parse(body, feed_url: normalized_url) do
        {:ok, payload} ->
          {:ok, [FeedDiscovery.candidate_from_feed_payload(normalized_url, payload)]}

        {:error, _reason} ->
          candidates = FeedDiscovery.discover_from_html(body, normalized_url)

          if candidates == [] do
            {:error, "No RSS/Atom feeds found on that page"}
          else
            {:ok, candidates}
          end
      end
    end
  end

  @impl true
  def fetch_feed(feed_url) when is_binary(feed_url) do
    with {:ok, payload, _entry_acc, _meta} <- fetch_feed(feed_url, []) do
      {:ok, payload}
    else
      {:error, reason, _meta} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def fetch_feed(feed_url, opts) when is_binary(feed_url) and is_list(opts) do
    with {:ok, normalized_url} <- normalize_url(feed_url),
         {:ok, agent} <- start_stream_agent(normalized_url, opts),
         {:ok, response} <- fetch_stream(normalized_url, agent) do
      finalize_stream_response(response, agent)
    else
      {:error, reason, meta} -> {:error, reason, meta}
      {:error, reason} -> {:error, reason, %{}}
    end
  end

  defp fetch(url) do
    case Req.get(req_options(url)) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Request failed with status #{status}"}

      {:error, error} ->
        {:error, "Request error: #{Exception.message(error)}"}
    end
  end

  defp fetch_stream(url, agent) do
    case Req.get(req_options(url, agent)) do
      {:ok, %Req.Response{} = response} ->
        {:ok, response}

      {:error, error} ->
        meta = agent_meta(agent)
        stop_stream_agent(agent)
        {:error, "Request error: #{Exception.message(error)}", meta}
    end
  end

  defp start_stream_agent(url, opts) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])

    parser_opts = [
      feed_url: url,
      max_items: Keyword.get(opts, :max_items, Keyword.get(fetch_config, :max_items, 500)),
      on_entry: Keyword.get(opts, :on_entry),
      entry_acc: Keyword.get(opts, :entry_acc)
    ]

    case Saxy.Partial.new(
           Icarurss.Reader.FeedParser.SaxyHandler,
           parser_opts |> Icarurss.Reader.FeedParser.SaxyHandler.initial_state(),
           character_data_max_length:
             Keyword.get(fetch_config, :character_data_max_length, 65_536)
         ) do
      {:ok, partial} ->
        Agent.start_link(fn ->
          %{
            partial: partial,
            bytes: 0,
            max_bytes:
              Keyword.get(opts, :max_bytes, Keyword.get(fetch_config, :max_bytes, 25_000_000)),
            error: nil,
            halted?: false,
            halted_reason: nil,
            final_state: nil,
            started_at: System.monotonic_time()
          }
        end)

      {:error, error} ->
        {:error, "Could not initialize feed parser: #{Exception.message(error)}"}
    end
  end

  defp finalize_stream_response(%Req.Response{status: status}, agent)
       when status not in 200..299 do
    meta = agent_meta(agent) |> Map.put(:http_status, status)
    stop_stream_agent(agent)
    {:error, "Request failed with status #{status}", meta}
  end

  defp finalize_stream_response(%Req.Response{status: status}, agent) do
    result =
      Agent.get_and_update(agent, fn
        %{error: error} = state when not is_nil(error) ->
          {{:error, error, stream_meta(state, status)}, state}

        %{halted?: true, final_state: final_state} = state ->
          case FeedParser.payload_from_state(final_state) do
            {:ok, payload} ->
              {{:ok, payload, final_state.entry_acc, stream_meta(state, status, final_state)},
               state}

            {:error, reason} ->
              {{:error, reason, stream_meta(state, status, final_state)}, state}
          end

        %{partial: partial} = state ->
          case Saxy.Partial.terminate(partial) do
            {:ok, final_state} ->
              case FeedParser.payload_from_state(final_state) do
                {:ok, payload} ->
                  {{:ok, payload, final_state.entry_acc, stream_meta(state, status, final_state)},
                   %{state | final_state: final_state}}

                {:error, reason} ->
                  {{:error, reason, stream_meta(state, status, final_state)},
                   %{state | final_state: final_state}}
              end

            {:error, error} ->
              {{:error, "Could not parse feed XML: #{Exception.message(error)}",
                stream_meta(state, status)}, state}
          end
      end)

    stop_stream_agent(agent)
    result
  end

  defp stream_into(agent) do
    fn {:data, data}, {req, resp} ->
      case parse_stream_chunk(agent, data) do
        :cont -> {:cont, {req, resp}}
        :halt -> {:halt, {req, resp}}
      end
    end
  end

  defp parse_stream_chunk(agent, data) do
    Agent.get_and_update(agent, fn
      %{error: error} = state when not is_nil(error) ->
        {:halt, state}

      %{halted?: true} = state ->
        {:halt, state}

      state ->
        bytes = state.bytes + byte_size(data)

        cond do
          max_bytes_exceeded?(bytes, state.max_bytes) ->
            reason = "Feed response exceeded max size of #{state.max_bytes} bytes"
            {:halt, %{state | bytes: bytes, error: reason, halted?: true}}

          true ->
            case Saxy.Partial.parse(state.partial, data) do
              {:cont, partial} ->
                {:cont, %{state | partial: partial, bytes: bytes}}

              {:halt, final_state} ->
                {:halt,
                 %{
                   state
                   | bytes: bytes,
                     halted?: true,
                     halted_reason: final_state.halted_reason,
                     final_state: final_state
                 }}

              {:halt, final_state, _rest} ->
                {:halt,
                 %{
                   state
                   | bytes: bytes,
                     halted?: true,
                     halted_reason: final_state.halted_reason,
                     final_state: final_state
                 }}

              {:error, error} ->
                reason = "Could not parse feed XML: #{Exception.message(error)}"
                {:halt, %{state | bytes: bytes, error: reason, halted?: true}}
            end
        end
    end)
  end

  defp max_bytes_exceeded?(_bytes, max_bytes) when max_bytes in [nil, 0], do: false
  defp max_bytes_exceeded?(bytes, max_bytes), do: bytes > max_bytes

  defp stream_meta(state, status), do: stream_meta(state, status, state.final_state)

  defp stream_meta(state, status, final_state) do
    %{
      http_status: status,
      bytes: state.bytes,
      parsed_items: parsed_items(final_state),
      duration_ms:
        System.convert_time_unit(
          System.monotonic_time() - state.started_at,
          :native,
          :millisecond
        ),
      halted_reason: state.halted_reason
    }
  end

  defp parsed_items(%{entry_count: entry_count}), do: entry_count
  defp parsed_items(_state), do: 0

  defp agent_meta(agent) do
    Agent.get(agent, &stream_meta(&1, nil))
  catch
    :exit, _ -> %{}
  end

  defp stop_stream_agent(agent) do
    Agent.stop(agent, :normal)
  catch
    :exit, _ -> :ok
  end

  defp req_options(url) do
    req_options(url, nil)
  end

  defp req_options(url, stream_agent) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])

    options = [
      url: url,
      headers: [{"user-agent", @user_agent}, {"accept-encoding", "identity"}],
      connect_options: [timeout: Keyword.get(fetch_config, :connect_timeout, 5_000)],
      pool_timeout: Keyword.get(fetch_config, :pool_timeout, 5_000),
      receive_timeout: Keyword.get(fetch_config, :receive_timeout, 30_000),
      retry: Keyword.get(fetch_config, :retry, false),
      max_retries: Keyword.get(fetch_config, :max_retries, 0)
    ]

    options =
      case stream_agent do
        nil -> options
        agent -> Keyword.put(options, :into, stream_into(agent))
      end

    Keyword.merge(options, Keyword.get(fetch_config, :req_options, []))
  end

  defp normalize_url(url_input) do
    trimmed = String.trim(url_input)

    cond do
      trimmed == "" ->
        {:error, "Please provide a URL"}

      true ->
        normalized =
          case URI.parse(trimmed) do
            %URI{scheme: scheme} when scheme in ["http", "https"] -> trimmed
            _ -> "https://" <> String.trim_leading(trimmed, "/")
          end

        case URI.parse(normalized) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            {:ok, URI.to_string(%URI{URI.parse(normalized) | fragment: nil})}

          _ ->
            {:error, "Please provide a valid URL"}
        end
    end
  end
end
