defmodule Icarurss.Reader.FeedSource.ReqSource do
  @moduledoc """
  Default feed source implementation backed by Req.
  """

  @behaviour Icarurss.Reader.FeedSource

  alias Icarurss.Reader.{FeedDiscovery, FeedParser, RefreshError}

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
         {stream_url, redirect_meta} <- resolve_stream_url(normalized_url),
         {:ok, agent} <- start_stream_agent(stream_url, opts, redirect_meta),
         {:ok, request, response} <- fetch_stream(stream_url, agent) do
      request
      |> finalize_stream_response(response, agent)
      |> maybe_fetch_buffered_fallback(stream_url, opts)
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
    case Req.run(req_options(url, agent)) do
      {%Req.Request{} = request, %Req.Response{} = response} ->
        {:ok, request, response}

      {%Req.Request{} = request, error} ->
        meta =
          agent_meta(agent)
          |> Map.put(:final_url, request_url(request))

        stop_stream_agent(agent)

        {:error,
         RefreshError.new(:request, "Request error: #{Exception.message(error)}",
           retryable?: true,
           permanent?: false,
           meta: meta
         ), meta}
    end
  end

  defp resolve_stream_url(url) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])
    max_redirects = Keyword.get(fetch_config, :max_redirects, 10)

    case resolve_redirects(url, max_redirects, 0) do
      {:ok, final_url, redirect_count} ->
        {final_url, %{redirect_count: redirect_count}}

      :error ->
        {url, %{redirect_count: 0}}
    end
  end

  defp resolve_redirects(url, redirects_left, redirect_count) when redirects_left <= 0 do
    {:ok, url, redirect_count}
  end

  defp resolve_redirects(url, redirects_left, redirect_count) do
    case request_redirect_response(url, :head) do
      {:ok, status, location} when status in 300..399 and is_binary(location) ->
        url
        |> resolve_location(location)
        |> resolve_redirects(redirects_left - 1, redirect_count + 1)

      {:ok, status, _location} when status in 300..399 ->
        {:ok, url, redirect_count}

      {:ok, status, _location} when status in [405, 501] ->
        resolve_redirects_with_get(url, redirects_left, redirect_count)

      {:ok, _status, _location} ->
        {:ok, url, redirect_count}

      :error ->
        :error
    end
  end

  defp resolve_redirects_with_get(url, redirects_left, redirect_count) do
    case request_redirect_response(url, :get) do
      {:ok, status, location} when status in 300..399 and is_binary(location) ->
        url
        |> resolve_location(location)
        |> resolve_redirects(redirects_left - 1, redirect_count + 1)

      {:ok, _status, _location} ->
        {:ok, url, redirect_count}

      :error ->
        :error
    end
  end

  defp request_redirect_response(url, method) do
    options =
      url
      |> req_options()
      |> Keyword.merge(method: method, redirect: false)

    case Req.run(options) do
      {%Req.Request{}, %Req.Response{status: status} = response} ->
        {:ok, status, response_header(response, "location")}

      _ ->
        :error
    end
  rescue
    _error -> :error
  end

  defp resolve_location(url, location) do
    url
    |> URI.parse()
    |> URI.merge(location)
    |> URI.to_string()
  end

  defp start_stream_agent(url, opts, redirect_meta) do
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
            normalizer: FeedParser.new_stream_normalizer_state(),
            preview_start: "",
            preview_current: "",
            http_status: nil,
            content_type: nil,
            content_length: nil,
            final_url: url,
            redirect_count: Map.get(redirect_meta, :redirect_count, 0),
            started_at: System.monotonic_time()
          }
        end)

      {:error, error} ->
        {:error, "Could not initialize feed parser: #{Exception.message(error)}"}
    end
  end

  defp finalize_stream_response(request, %Req.Response{status: status} = response, agent)
       when status not in 200..299 do
    meta =
      agent_meta(agent)
      |> put_response_meta(request, response)

    stop_stream_agent(agent)

    {:error,
     RefreshError.new(:http_status, "Request failed with status #{status}",
       retryable?: status in [408, 429, 500, 502, 503, 504],
       permanent?: status not in [408, 429, 500, 502, 503, 504],
       meta: meta
     ), meta}
  end

  defp finalize_stream_response(request, %Req.Response{status: status} = response, agent) do
    Agent.update(agent, &put_response_meta(&1, request, response))

    result =
      Agent.get_and_update(agent, fn
        %{error: error} = state when not is_nil(error) ->
          meta = stream_meta(state, status)
          {{:error, RefreshError.from(error, meta), meta}, state}

        %{halted?: true, final_state: final_state} = state ->
          case FeedParser.payload_from_state(final_state) do
            {:ok, payload} ->
              {{:ok, payload, final_state.entry_acc, stream_meta(state, status, final_state)},
               state}

            {:error, reason} ->
              meta = stream_meta(state, status, final_state)
              error = RefreshError.from(reason, meta)
              {{:error, error, meta}, state}
          end

        %{partial: partial} = state ->
          case Saxy.Partial.terminate(partial) do
            {:ok, final_state} ->
              case FeedParser.payload_from_state(final_state) do
                {:ok, payload} ->
                  {{:ok, payload, final_state.entry_acc, stream_meta(state, status, final_state)},
                   %{state | final_state: final_state}}

                {:error, reason} ->
                  meta = stream_meta(state, status, final_state)
                  error = RefreshError.from(reason, meta)
                  {{:error, error, meta}, %{state | final_state: final_state}}
              end

            {:error, error} ->
              meta = stream_meta(state, status)

              refresh_error =
                RefreshError.new(:parse, "Could not parse feed XML: #{Exception.message(error)}",
                  retryable?: false,
                  permanent?: true,
                  meta: meta
                )

              {{:error, refresh_error, meta}, state}
          end
      end)

    stop_stream_agent(agent)
    enrich_result_favicon(result)
  end

  defp maybe_fetch_buffered_fallback({:error, %RefreshError{} = error, meta} = result, url, opts) do
    if buffered_fallback_allowed?(error, meta, opts) do
      fetch_feed_buffered(url, opts, error, meta)
    else
      result
    end
  end

  defp maybe_fetch_buffered_fallback(result, _url, _opts), do: result

  defp buffered_fallback_allowed?(%RefreshError{kind: :parse}, meta, opts) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])

    Keyword.get(opts, :buffered_fallback, Keyword.get(fetch_config, :buffered_fallback, true)) and
      Map.get(meta, :halted_reason) == :parse_error and
      Map.get(meta, :parsed_items, 0) == 0 and
      plausible_feed_xml?(meta)
  end

  defp buffered_fallback_allowed?(_error, _meta, _opts), do: false

  defp plausible_feed_xml?(meta) do
    content_type = meta |> Map.get(:content_type) |> to_string() |> String.downcase()
    preview = meta |> Map.get(:preview_start) |> to_string() |> String.trim_leading()

    String.contains?(content_type, "xml") or
      String.starts_with?(preview, "<?xml") or
      String.starts_with?(preview, "<rss") or
      String.starts_with?(preview, "<feed") or
      String.starts_with?(preview, "<rdf:RDF")
  end

  defp fetch_feed_buffered(url, opts, original_error, original_meta) do
    started_at = System.monotonic_time()

    case Req.run(req_options(url)) do
      {%Req.Request{} = request, %Req.Response{status: status} = response}
      when status in 200..299 ->
        body = response.body |> to_string()
        bytes = byte_size(body)
        max_bytes = max_response_bytes(opts)

        if max_bytes_exceeded?(bytes, max_bytes) do
          meta = buffered_meta(request, response, body, started_at, original_meta)

          {:error,
           RefreshError.new(
             :too_large,
             "Feed response exceeded max size of #{max_bytes} bytes",
             retryable?: false,
             permanent?: true,
             meta: Map.put(meta, :halted_reason, :too_large)
           ), Map.put(meta, :halted_reason, :too_large)}
        else
          parse_buffered_body(
            body,
            request,
            response,
            started_at,
            opts,
            original_error,
            original_meta
          )
        end

      {%Req.Request{} = request, %Req.Response{status: status} = response} ->
        meta = buffered_meta(request, response, "", started_at, original_meta)

        {:error,
         RefreshError.new(:http_status, "Request failed with status #{status}",
           retryable?: status in [408, 429, 500, 502, 503, 504],
           permanent?: status not in [408, 429, 500, 502, 503, 504],
           meta: meta
         ), meta}

      {%Req.Request{} = request, error} ->
        meta =
          original_meta
          |> Map.put(:final_url, request_url(request))
          |> Map.put(:buffered_fallback?, true)
          |> Map.put(:buffered_fallback_error, Exception.message(error))

        {:error,
         RefreshError.new(:request, "Request error: #{Exception.message(error)}",
           retryable?: true,
           permanent?: false,
           meta: meta
         ), meta}
    end
  rescue
    error ->
      meta =
        original_meta
        |> Map.put(:buffered_fallback?, true)
        |> Map.put(:buffered_fallback_error, Exception.message(error))

      {:error, RefreshError.from(original_error, meta), meta}
  end

  defp parse_buffered_body(
         body,
         request,
         response,
         started_at,
         opts,
         original_error,
         original_meta
       ) do
    case FeedParser.parse_stream_with_state([body], parser_opts(request_url(request), opts)) do
      {:ok, payload, final_state} ->
        meta =
          request
          |> buffered_meta(response, body, started_at, original_meta)
          |> Map.put(:parsed_items, final_state.entry_count)
          |> Map.put(:partial_halt?, false)
          |> Map.put(:halted_reason, nil)

        {:ok, payload, final_state.entry_acc, meta}
        |> enrich_result_favicon()

      {:error, reason} ->
        meta =
          request
          |> buffered_meta(response, body, started_at, original_meta)
          |> Map.put(:buffered_fallback_error, reason)

        {:error, RefreshError.from(original_error, meta), meta}
    end
  end

  defp parser_opts(url, opts) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])

    [
      feed_url: url,
      max_items: Keyword.get(opts, :max_items, Keyword.get(fetch_config, :max_items, 500)),
      on_entry: Keyword.get(opts, :on_entry),
      entry_acc: Keyword.get(opts, :entry_acc),
      character_data_max_length: Keyword.get(fetch_config, :character_data_max_length, 65_536)
    ]
  end

  defp buffered_meta(request, response, body, started_at, original_meta) do
    bytes = byte_size(body)

    original_meta
    |> Map.merge(%{
      http_status: response.status,
      bytes: bytes,
      bytes_consumed: bytes,
      content_type: response_header(response, "content-type"),
      content_length: response_content_length(response),
      full_content_length: response_content_length(response),
      final_url: request_url(request),
      preview_start: FeedParser.escaped_preview(body),
      preview_current: FeedParser.escaped_preview(body),
      duration_ms:
        System.convert_time_unit(
          System.monotonic_time() - started_at,
          :native,
          :millisecond
        ),
      buffered_fallback?: true
    })
    |> Map.put(:stream_error, format_fallback_stream_error(original_meta))
  end

  defp format_fallback_stream_error(meta) do
    case Map.get(meta, :halted_reason) do
      nil -> nil
      reason -> inspect(reason)
    end
  end

  defp enrich_result_favicon({:ok, payload, entry_acc, meta}) do
    {:ok, enrich_payload_favicon(payload), entry_acc, meta}
  end

  defp enrich_result_favicon(result), do: result

  defp enrich_payload_favicon(%{site_url: site_url} = payload) do
    favicon_url =
      fetch_html_favicon(site_url) ||
        validate_conventional_favicon(payload[:favicon_url], payload[:base_url])

    Map.put(payload, :favicon_url, favicon_url)
  end

  defp enrich_payload_favicon(payload), do: payload

  defp fetch_html_favicon(nil), do: nil

  defp fetch_html_favicon(site_url) when is_binary(site_url) do
    with {:ok, response} <- fetch(site_url) do
      response.body
      |> to_string()
      |> FeedDiscovery.favicon_url_from_html(site_url)
    else
      _ -> nil
    end
  end

  defp validate_conventional_favicon(nil, _base_url), do: nil

  defp validate_conventional_favicon(favicon_url, base_url) when is_binary(favicon_url) do
    if conventional_favicon?(favicon_url, base_url) do
      verified_conventional_favicon(favicon_url)
    else
      favicon_url
    end
  end

  defp conventional_favicon?(favicon_url, base_url)
       when is_binary(favicon_url) and is_binary(base_url) do
    favicon_url == base_url <> "/favicon.ico"
  end

  defp conventional_favicon?(_favicon_url, _base_url), do: false

  defp verified_conventional_favicon(url) do
    case Req.head(req_options(url)) do
      {:ok, %Req.Response{status: status}} when status in 200..399 -> url
      {:ok, %Req.Response{status: status}} when status in [404, 410] -> nil
      _ -> url
    end
  end

  defp stream_into(agent) do
    fn {:data, data}, {req, resp} ->
      update_response_meta(agent, req, resp)

      case parse_stream_data(agent, data) do
        :cont -> {:cont, {req, resp}}
        :halt -> {:halt, {req, resp}}
      end
    end
  end

  defp parse_stream_data(agent, data) do
    data
    |> stream_data_chunks()
    |> Enum.reduce_while(:cont, fn chunk, :cont ->
      case parse_stream_chunk(agent, chunk) do
        :cont -> {:cont, :cont}
        :halt -> {:halt, :halt}
      end
    end)
  end

  defp stream_data_chunks(data) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])

    case Keyword.get(fetch_config, :stream_chunk_bytes) do
      size when is_integer(size) and size > 0 ->
        chunks = for <<chunk::binary-size(size) <- data>>, do: chunk
        append_stream_remainder(chunks, data, size)

      _ ->
        [data]
    end
  end

  defp append_stream_remainder(chunks, data, size) do
    remainder_size = rem(byte_size(data), size)

    if remainder_size == 0 do
      chunks
    else
      offset = byte_size(data) - remainder_size
      chunks ++ [binary_part(data, offset, remainder_size)]
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

            error =
              RefreshError.new(:too_large, reason,
                retryable?: false,
                permanent?: true,
                meta: %{halted_reason: :too_large}
              )

            {:halt,
             %{state | bytes: bytes, error: error, halted?: true, halted_reason: :too_large}}

          true ->
            case FeedParser.normalize_stream_chunk(data, state.normalizer) do
              {:cont, "", normalizer} ->
                {:cont, %{state | normalizer: normalizer, bytes: bytes}}

              {:cont, normalized_data, normalizer} ->
                parse_normalized_stream_chunk(
                  %{state | normalizer: normalizer},
                  normalized_data,
                  bytes
                )

              {:error, %RefreshError{} = error, normalizer} ->
                {:halt,
                 %{
                   state
                   | normalizer: normalizer,
                     bytes: bytes,
                     error: error,
                     halted?: true,
                     halted_reason: error.meta[:halted_reason] || :non_feed,
                     preview_start: error.meta[:preview_start] || state.preview_start
                 }}
            end
        end
    end)
  end

  defp parse_normalized_stream_chunk(state, data, bytes) do
    preview_current = FeedParser.escaped_preview(data)

    state =
      state
      |> Map.put(:bytes, bytes)
      |> Map.put(:preview_current, preview_current)
      |> Map.update(:preview_start, preview_current, fn
        "" -> preview_current
        existing -> existing
      end)

    case Saxy.Partial.parse(state.partial, data) do
      {:cont, partial} ->
        {:cont, %{state | partial: partial}}

      {:halt, final_state} ->
        halt_with_final_state(state, final_state)

      {:halt, final_state, _rest} ->
        halt_with_final_state(state, final_state)

      {:error, error} ->
        reason = "Could not parse feed XML: #{Exception.message(error)}"

        refresh_error =
          RefreshError.new(:parse, reason,
            retryable?: false,
            permanent?: true,
            meta: %{halted_reason: :parse_error, preview_current: preview_current}
          )

        {:halt, %{state | error: refresh_error, halted?: true, halted_reason: :parse_error}}
    end
  end

  defp halt_with_final_state(state, final_state) do
    {:halt,
     %{
       state
       | halted?: true,
         halted_reason: final_state.halted_reason,
         final_state: final_state
     }}
  end

  defp max_bytes_exceeded?(_bytes, max_bytes) when max_bytes in [nil, 0], do: false
  defp max_bytes_exceeded?(bytes, max_bytes), do: bytes > max_bytes

  defp max_response_bytes(opts) do
    fetch_config = Application.get_env(:icarurss, :feed_fetch, [])
    Keyword.get(opts, :max_bytes, Keyword.get(fetch_config, :max_bytes, 25_000_000))
  end

  defp stream_meta(state, status), do: stream_meta(state, status, state.final_state)

  defp stream_meta(state, status, final_state) do
    %{
      http_status: status,
      bytes: state.bytes,
      bytes_consumed: state.bytes,
      parsed_items: parsed_items(final_state),
      content_type: state.content_type,
      content_length: state.content_length,
      full_content_length: state.content_length,
      final_url: state.final_url,
      redirect_count: state.redirect_count,
      partial_halt?: not is_nil(state.error) or state.halted?,
      preview_start: state.preview_start,
      preview_current: state.preview_current,
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

  defp update_response_meta(agent, request, response) do
    Agent.update(agent, &put_response_meta(&1, request, response))
  catch
    :exit, _ -> :ok
  end

  defp put_response_meta(state, request, response) when is_map(state) do
    state
    |> Map.put(:http_status, response.status)
    |> Map.put(:content_type, response_header(response, "content-type"))
    |> Map.put(:content_length, response_content_length(response))
    |> Map.put(:final_url, request_url(request))
  end

  defp response_header(response, name) do
    response
    |> Req.Response.get_header(name)
    |> List.first()
  end

  defp response_content_length(response) do
    response
    |> response_header("content-length")
    |> case do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _ -> nil
        end
    end
  end

  defp request_url(%Req.Request{url: %URI{} = uri}), do: URI.to_string(uri)
  defp request_url(%Req.Request{url: url}) when is_binary(url), do: url
  defp request_url(_request), do: nil

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
