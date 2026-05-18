defmodule Icarurss.Reader do
  @moduledoc """
  Reader domain context: folders, feeds, and articles scoped per user.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Icarurss.Accounts.User
  alias Icarurss.Reader.{Article, Feed, Folder, HtmlSanitizer, Opml, RefreshError, Setting}
  alias Icarurss.Repo
  alias Icarurss.Workers.RefreshFeedWorker

  @type article_filter :: :all | :unread | :starred
  @type list_articles_opt ::
          {:filter, article_filter()}
          | {:feed_id, integer()}
          | {:folder_id, integer()}
          | {:search, String.t()}
          | {:limit, pos_integer()}

  def user_topic(user_id) when is_integer(user_id), do: "reader:user:#{user_id}"

  ## Reader Setting APIs

  def get_reader_setting(%User{id: user_id}) do
    Repo.get_by(Setting, user_id: user_id)
  end

  def get_or_create_reader_setting(%User{id: user_id}) do
    case get_reader_setting(%User{id: user_id}) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{user_id: user_id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: :user_id)

        Repo.get_by!(Setting, user_id: user_id)

      %Setting{} = setting ->
        setting
    end
  end

  def change_reader_setting(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  def update_reader_setting(%User{} = user, attrs) when is_map(attrs) do
    user
    |> get_or_create_reader_setting()
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  ## Folder APIs

  def list_folders(%User{id: user_id}) do
    Repo.all(
      from folder in Folder,
        where: folder.user_id == ^user_id,
        order_by: [asc: folder.position, asc: folder.name]
    )
  end

  def list_folders_with_feeds(%User{id: user_id}) do
    feeds_query =
      from feed in Feed,
        where: feed.user_id == ^user_id,
        order_by: [asc: feed.title, asc: feed.id]

    Repo.all(
      from folder in Folder,
        where: folder.user_id == ^user_id,
        order_by: [asc: folder.position, asc: folder.name],
        preload: [feeds: ^feeds_query]
    )
  end

  def create_folder(%User{id: user_id}, attrs \\ %{}) do
    %Folder{user_id: user_id}
    |> Folder.changeset(attrs)
    |> Repo.insert()
  end

  def update_folder(%Folder{} = folder, attrs) do
    folder
    |> Folder.changeset(attrs)
    |> Repo.update()
  end

  def delete_folder(%Folder{} = folder), do: Repo.delete(folder)

  def change_folder(%Folder{} = folder, attrs \\ %{}) do
    Folder.changeset(folder, attrs)
  end

  ## Feed APIs

  def list_feeds(%User{id: user_id}) do
    Repo.all(
      from feed in Feed,
        where: feed.user_id == ^user_id,
        order_by: [asc: feed.title, asc: feed.id]
    )
  end

  def list_all_feed_ids(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5_000)

    Repo.all(
      from feed in Feed,
        order_by: [asc: feed.id],
        select: feed.id,
        limit: ^limit
    )
  end

  def list_refreshable_feed_ids(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5_000)
    now = DateTime.utc_now(:second)

    Repo.all(
      from feed in Feed,
        where: is_nil(feed.next_refresh_after) or feed.next_refresh_after <= ^now,
        order_by: [asc: feed.id],
        select: feed.id,
        limit: ^limit
    )
  end

  def get_feed(feed_id) when is_integer(feed_id), do: Repo.get(Feed, feed_id)

  def list_ungrouped_feeds(%User{id: user_id}) do
    Repo.all(
      from feed in Feed,
        where: feed.user_id == ^user_id and is_nil(feed.folder_id),
        order_by: [asc: feed.title, asc: feed.id]
    )
  end

  def get_feed_for_user!(%User{id: user_id}, feed_id) do
    Repo.get_by!(Feed, id: feed_id, user_id: user_id)
  end

  def create_feed(%User{id: user_id}, attrs \\ %{}) do
    %Feed{user_id: user_id}
    |> Feed.changeset(attrs)
    |> Repo.insert()
  end

  def discover_feed_candidates(url) when is_binary(url) do
    feed_source_module().discover(url)
  end

  def subscribe_feed_from_candidate(%User{} = user, candidate, opts \\ [])
      when is_map(candidate) do
    folder_id = normalize_folder_id_for_user(user, Keyword.get(opts, :folder_id))

    attrs = %{
      feed_url: map_value(candidate, :feed_url),
      title: map_value(candidate, :title),
      site_url: map_value(candidate, :site_url),
      base_url: map_value(candidate, :base_url),
      favicon_url: map_value(candidate, :favicon_url),
      folder_id: folder_id
    }

    case create_feed(user, attrs) do
      {:ok, feed} ->
        refresh_result =
          refresh_feed(feed, initial_mark_read: Keyword.get(opts, :initial_mark_read, false))

        {:ok, feed, refresh_result}

      {:error, _} = error ->
        error
    end
  end

  def update_feed(%Feed{} = feed, attrs) do
    feed
    |> Feed.changeset(attrs)
    |> Repo.update()
  end

  def delete_feed(%Feed{} = feed), do: Repo.delete(feed)

  def change_feed(%Feed{} = feed, attrs \\ %{}) do
    Feed.changeset(feed, attrs)
  end

  def delete_all_feeds_and_articles_for_user(%User{id: user_id}) do
    feed_count =
      Repo.aggregate(from(feed in Feed, where: feed.user_id == ^user_id), :count, :id)

    article_count =
      Repo.aggregate(from(article in Article, where: article.user_id == ^user_id), :count, :id)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :articles,
        from(article in Article, where: article.user_id == ^user_id)
      )
      |> Ecto.Multi.delete_all(:feeds, from(feed in Feed, where: feed.user_id == ^user_id))

    case Repo.transaction(multi) do
      {:ok, _result} ->
        {:ok, %{feeds_deleted: feed_count, articles_deleted: article_count}}

      {:error, _step, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  def refresh_user_feeds(%User{} = user, opts \\ []) do
    initial_mark_read? = Keyword.get(opts, :initial_mark_read, false)
    max_concurrency = Keyword.get(opts, :max_concurrency, feed_refresh_max_concurrency())

    list_feeds(user)
    |> refresh_feeds(initial_mark_read?, max_concurrency)
  end

  def refresh_all_feeds(opts \\ []) do
    initial_mark_read? = Keyword.get(opts, :initial_mark_read, false)
    max_concurrency = Keyword.get(opts, :max_concurrency, feed_refresh_max_concurrency())
    limit = Keyword.get(opts, :limit, 5_000)
    force? = Keyword.get(opts, :force, false)

    refreshable_query =
      if force? do
        from(feed in Feed, order_by: [asc: feed.id], limit: ^limit)
      else
        now = DateTime.utc_now(:second)

        from feed in Feed,
          where: is_nil(feed.next_refresh_after) or feed.next_refresh_after <= ^now,
          order_by: [asc: feed.id],
          limit: ^limit
      end

    Repo.all(refreshable_query)
    |> refresh_feeds(initial_mark_read?, max_concurrency)
  end

  def refresh_feed(%Feed{} = feed, opts \\ []) do
    initial_mark_read? = Keyword.get(opts, :initial_mark_read, false)
    source_module = feed_source_module()

    if not Keyword.get(opts, :force, false) and refresh_deferred?(feed) do
      {:ok, empty_ingest_stats()}
    else
      if function_exported?(source_module, :fetch_feed, 2) do
        refresh_feed_streaming(source_module, feed, initial_mark_read?)
      else
        refresh_feed_compat(source_module, feed, initial_mark_read?)
      end
    end
  end

  defp refresh_feed_streaming(source_module, %Feed{} = feed, initial_mark_read?) do
    fetched_at = DateTime.utc_now(:second)

    entry_callback = fn entry, stats ->
      ingest_entry(feed, entry, fetched_at, initial_mark_read?, stats)
    end

    case source_module.fetch_feed(feed.feed_url,
           feed_id: feed.id,
           on_entry: entry_callback,
           entry_acc: empty_ingest_stats()
         ) do
      {:ok, payload, stats, meta} ->
        with {:ok, updated_feed} <- update_feed_from_payload(feed, payload) do
          log_refresh_success(updated_feed, stats, meta)
          emit_refresh_success(updated_feed, stats, meta)
          maybe_broadcast_feed_refresh(updated_feed, stats)
          {:ok, stats}
        end

      {:error, reason, meta} ->
        error = RefreshError.from(reason, meta)
        log_refresh_error(feed, error, meta)
        emit_refresh_error(feed, error)
        {:error, error}

      {:error, reason} ->
        error = RefreshError.from(reason, %{})
        log_refresh_error(feed, error, %{})
        emit_refresh_error(feed, error)
        {:error, error}
    end
  end

  defp refresh_feed_compat(source_module, %Feed{} = feed, initial_mark_read?) do
    case source_module.fetch_feed(feed.feed_url) do
      {:ok, payload} ->
        with {:ok, updated_feed} <- update_feed_from_payload(feed, payload) do
          fetched_at = DateTime.utc_now(:second)

          stats =
            ingest_entries(updated_feed, payload[:entries] || [], fetched_at, initial_mark_read?)

          maybe_broadcast_feed_refresh(updated_feed, stats)
          {:ok, stats}
        end

      {:error, reason} ->
        classified_error = RefreshError.from(reason, %{})
        emit_refresh_error(feed, classified_error)
        {:error, classified_error}
    end
  end

  def refresh_error_retryable?(reason), do: RefreshError.retryable?(reason)

  ## OPML APIs

  def export_opml_for_user(%User{} = user) do
    {:ok, Opml.generate(list_folders_with_feeds(user), list_ungrouped_feeds(user))}
  end

  def import_opml_for_user(%User{} = user, opml_xml) when is_binary(opml_xml) do
    with {:ok, entries} <- Opml.parse(opml_xml) do
      existing_folders = list_folders(user)

      initial_folder_lookup =
        Map.new(existing_folders, fn folder -> {folder.name, folder} end)

      initial_next_folder_position = next_folder_position(existing_folders)

      existing_feed_urls =
        user
        |> list_feeds()
        |> Enum.map(& &1.feed_url)
        |> MapSet.new()

      {stats, _folder_lookup, _feed_urls, _next_position, imported_feeds} =
        Enum.reduce(
          entries,
          {%{folders_created: 0, feeds_added: 0, feeds_skipped: 0}, initial_folder_lookup,
           existing_feed_urls, initial_next_folder_position, []},
          fn entry, {stats, folder_lookup, feed_urls, next_position, imported_feeds} ->
            folder_name = map_value(entry, :folder_name)

            {folder_id, folder_lookup, next_position, stats} =
              ensure_folder_for_import(
                user,
                folder_name,
                folder_lookup,
                next_position,
                stats
              )

            feed_url = map_value(entry, :feed_url)
            title = map_value(entry, :title)
            site_url = map_value(entry, :site_url)
            base_url = origin_url(site_url) || origin_url(feed_url)

            cond do
              not present?(feed_url) ->
                {%{stats | feeds_skipped: stats.feeds_skipped + 1}, folder_lookup, feed_urls,
                 next_position, imported_feeds}

              MapSet.member?(feed_urls, feed_url) ->
                {%{stats | feeds_skipped: stats.feeds_skipped + 1}, folder_lookup, feed_urls,
                 next_position, imported_feeds}

              true ->
                attrs = %{
                  folder_id: folder_id,
                  feed_url: feed_url,
                  title: title,
                  site_url: site_url,
                  base_url: base_url,
                  favicon_url: favicon_url_for(base_url)
                }

                case create_feed(user, attrs) do
                  {:ok, feed} ->
                    {%{stats | feeds_added: stats.feeds_added + 1}, folder_lookup,
                     MapSet.put(feed_urls, feed.feed_url), next_position, [feed | imported_feeds]}

                  {:error, _changeset} ->
                    {%{stats | feeds_skipped: stats.feeds_skipped + 1}, folder_lookup, feed_urls,
                     next_position, imported_feeds}
                end
            end
          end
        )

      {:ok, Map.merge(stats, queue_initial_feed_refreshes(imported_feeds))}
    end
  end

  ## Article APIs

  def list_articles_for_user(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    user_id
    |> article_list_query(opts)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_article_for_user!(%User{id: user_id}, article_id) do
    Repo.one!(
      from article in Article,
        join: feed in assoc(article, :feed),
        where:
          article.id == ^article_id and article.user_id == ^user_id and feed.user_id == ^user_id,
        preload: [feed: feed]
    )
  end

  def create_article(%User{id: user_id}, %Feed{id: feed_id}, attrs \\ %{}) do
    %Article{user_id: user_id, feed_id: feed_id}
    |> Article.changeset(attrs)
    |> Repo.insert()
  end

  def update_article(%Article{} = article, attrs) do
    article
    |> Article.changeset(attrs)
    |> Repo.update()
  end

  def mark_article_read(%Article{} = article) do
    case update_article(article, %{is_read: true}) do
      {:ok, %Article{} = updated_article} = result ->
        broadcast_articles_read(updated_article.user_id)
        result

      {:error, _changeset} = error ->
        error
    end
  end

  def mark_article_starred(%Article{} = article, starred?) when is_boolean(starred?) do
    update_article(article, %{is_starred: starred?})
  end

  def mark_all_read_for_user(%User{id: user_id}, opts \\ []) do
    now = DateTime.utc_now(:second)

    {count, _} =
      user_id
      |> article_update_scope_query(opts)
      |> Repo.update_all(set: [is_read: true, updated_at: now])

    if count > 0 do
      broadcast_articles_read(user_id)
    end

    count
  end

  def unread_count_for_user(%User{id: user_id}) do
    Repo.aggregate(
      from(article in Article, where: article.user_id == ^user_id and article.is_read == false),
      :count,
      :id
    )
  end

  def feed_unread_counts(%User{id: user_id}) do
    Repo.all(
      from article in Article,
        where: article.user_id == ^user_id and article.is_read == false,
        group_by: article.feed_id,
        select: {article.feed_id, count(article.id)}
    )
    |> Map.new()
  end

  defp update_feed_from_payload(%Feed{} = feed, payload) do
    attrs = %{
      title: payload[:title] || feed.title,
      site_url: payload[:site_url] || feed.site_url,
      base_url: payload[:base_url] || feed.base_url,
      favicon_url: favicon_url_from_payload(feed, payload),
      last_fetched_at: DateTime.utc_now(:second),
      last_refresh_error: nil,
      refresh_status: "ok",
      refresh_error_kind: nil,
      refresh_failure_count: 0,
      last_refresh_failed_at: nil,
      next_refresh_after: nil
    }

    update_feed(feed, attrs)
  end

  defp favicon_url_from_payload(%Feed{} = feed, payload) do
    case Map.fetch(payload, :favicon_url) do
      {:ok, nil} ->
        if conventional_favicon?(feed.favicon_url, payload[:base_url] || feed.base_url) do
          nil
        else
          feed.favicon_url
        end

      {:ok, favicon_url} ->
        favicon_url

      :error ->
        feed.favicon_url
    end
  end

  defp conventional_favicon?(favicon_url, base_url)
       when is_binary(favicon_url) and is_binary(base_url) do
    favicon_url == base_url <> "/favicon.ico"
  end

  defp conventional_favicon?(_favicon_url, _base_url), do: false

  defp ingest_entries(feed, entries, fetched_at, initial_mark_read?) do
    Enum.reduce(entries, empty_ingest_stats(), fn entry, acc ->
      ingest_entry(feed, entry, fetched_at, initial_mark_read?, acc)
    end)
  end

  defp ingest_entry(feed, entry, fetched_at, initial_mark_read?, acc) do
    attrs = normalized_article_attrs(entry, fetched_at)

    case find_existing_article(feed.user_id, feed.id, attrs.guid, attrs.url) do
      nil ->
        case create_article(
               %User{id: feed.user_id},
               feed,
               Map.put(attrs, :is_read, initial_mark_read?)
             ) do
          {:ok, _article} -> %{acc | inserted: acc.inserted + 1}
          {:error, _changeset} -> %{acc | skipped: acc.skipped + 1}
        end

      %Article{} = existing_article ->
        case update_article(existing_article, attrs) do
          {:ok, _article} -> %{acc | updated: acc.updated + 1}
          {:error, _changeset} -> %{acc | skipped: acc.skipped + 1}
        end
    end
  end

  defp empty_ingest_stats, do: %{inserted: 0, updated: 0, skipped: 0}

  defp normalized_article_attrs(entry, fetched_at) do
    title = map_value(entry, :title) || "(untitled)"
    url = map_value(entry, :url)
    guid = normalize_guid(map_value(entry, :guid), url, title, fetched_at)
    summary_html = map_value(entry, :summary_html) |> HtmlSanitizer.sanitize_fragment()
    content_html = map_value(entry, :content_html) |> HtmlSanitizer.sanitize_fragment()

    %{
      guid: guid,
      url: url,
      title: title,
      author: map_value(entry, :author),
      summary_html: summary_html,
      content_html: content_html,
      published_at: map_value(entry, :published_at) || fetched_at,
      fetched_at: fetched_at
    }
  end

  defp normalize_guid(guid, url, title, datetime) do
    cond do
      is_binary(guid) and String.trim(guid) != "" ->
        guid

      is_binary(url) and String.trim(url) != "" ->
        url

      true ->
        :crypto.hash(:sha256, "#{title}|#{DateTime.to_iso8601(datetime)}")
        |> Base.encode16(case: :lower)
    end
  end

  defp find_existing_article(user_id, feed_id, guid, url) do
    base_query =
      from article in Article,
        where: article.user_id == ^user_id and article.feed_id == ^feed_id

    query =
      cond do
        present?(guid) and present?(url) ->
          from article in base_query, where: article.guid == ^guid or article.url == ^url

        present?(guid) ->
          from article in base_query, where: article.guid == ^guid

        present?(url) ->
          from article in base_query, where: article.url == ^url

        true ->
          nil
      end

    if query do
      Repo.one(query)
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp article_list_query(user_id, opts) do
    search = opts |> Keyword.get(:search, "") |> String.trim() |> String.downcase()

    from(article in Article,
      join: feed in assoc(article, :feed),
      where: article.user_id == ^user_id and feed.user_id == ^user_id,
      preload: [feed: feed],
      order_by: [desc: article.published_at, desc: article.inserted_at]
    )
    |> maybe_filter_by_feed(opts[:feed_id])
    |> maybe_filter_by_folder(opts[:folder_id])
    |> maybe_filter_by_mode(opts[:filter])
    |> maybe_filter_by_search(search, user_id)
  end

  defp article_update_scope_query(user_id, opts) do
    from(article in Article, where: article.user_id == ^user_id)
    |> maybe_filter_by_feed(opts[:feed_id])
    |> maybe_filter_by_folder(opts[:folder_id], user_id)
    |> maybe_filter_by_mode(opts[:filter])
  end

  defp maybe_filter_by_feed(query, nil), do: query

  defp maybe_filter_by_feed(query, feed_id) when is_integer(feed_id) do
    from article in query, where: article.feed_id == ^feed_id
  end

  defp maybe_filter_by_folder(query, nil), do: query

  defp maybe_filter_by_folder(query, folder_id) when is_integer(folder_id) do
    from [article, feed] in query, where: feed.folder_id == ^folder_id
  end

  defp maybe_filter_by_folder(query, folder_id, user_id) when is_integer(folder_id) do
    feed_ids =
      from(feed in Feed,
        where: feed.user_id == ^user_id and feed.folder_id == ^folder_id,
        select: feed.id
      )

    from article in query, where: article.feed_id in subquery(feed_ids)
  end

  defp maybe_filter_by_folder(query, nil, _user_id), do: query

  defp maybe_filter_by_mode(query, :unread),
    do: from(article in query, where: article.is_read == false)

  defp maybe_filter_by_mode(query, :starred),
    do: from(article in query, where: article.is_starred == true)

  defp maybe_filter_by_mode(query, _), do: query

  defp maybe_filter_by_search(query, "", _user_id), do: query

  defp maybe_filter_by_search(query, search, user_id) do
    if article_search_available?() do
      maybe_filter_by_search_fts(query, search, user_id)
    else
      maybe_filter_by_search_like(query, search)
    end
  end

  defp maybe_filter_by_search_like(query, search) do
    pattern = "%#{search}%"

    from [article, feed] in query,
      where:
        like(fragment("lower(?)", article.title), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", article.content_html), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", article.summary_html), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", article.url), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", feed.title), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", feed.feed_url), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", feed.site_url), ^pattern) or
          like(fragment("lower(coalesce(?, ''))", feed.base_url), ^pattern)
  end

  defp maybe_filter_by_search_fts(query, search, user_id) do
    case build_fts_query(search) do
      nil ->
        maybe_filter_by_search_like(query, search)

      fts_query ->
        pattern = "%#{search}%"

        ranked_search_query =
          from search_entry in fragment(
                 """
                 SELECT rowid AS article_id, bm25(articles_search) AS rank
                 FROM articles_search
                 WHERE user_id = ? AND articles_search MATCH ?
                 """,
                 ^user_id,
                 ^fts_query
               ),
               select: %{
                 article_id: field(search_entry, :article_id),
                 rank: field(search_entry, :rank)
               }

        query =
          from [article, feed] in query,
            left_join: search_entry in subquery(ranked_search_query),
            on: search_entry.article_id == article.id,
            where:
              not is_nil(search_entry.article_id) or
                like(fragment("lower(coalesce(?, ''))", article.url), ^pattern) or
                like(fragment("lower(coalesce(?, ''))", feed.feed_url), ^pattern)

        prepend_order_by(
          query,
          [article, _feed, search_entry],
          asc: fragment("coalesce(?, 1000000000)", field(search_entry, :rank)),
          desc: article.published_at,
          desc: article.inserted_at
        )
    end
  end

  defp article_search_available? do
    case Repo.query(
           "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'articles_search'"
         ) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp build_fts_query(search) do
    search
    |> String.downcase()
    |> String.replace(~r/[^[:alnum:]\s]/u, " ")
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.uniq()
    |> case do
      [] ->
        nil

      tokens ->
        Enum.map_join(tokens, " AND ", fn token -> "\"#{token}\"*" end)
    end
  end

  defp reduce_refresh_results(results) do
    Enum.reduce(results, %{ok: 0, error: 0, inserted: 0, updated: 0, skipped: 0}, fn
      {:ok, {:ok, stats}}, acc ->
        %{
          ok: acc.ok + 1,
          error: acc.error,
          inserted: acc.inserted + stats.inserted,
          updated: acc.updated + stats.updated,
          skipped: acc.skipped + stats.skipped
        }

      _other, acc ->
        %{acc | error: acc.error + 1}
    end)
  end

  defp maybe_broadcast_feed_refresh(feed, stats) do
    Phoenix.PubSub.broadcast(
      Icarurss.PubSub,
      user_topic(feed.user_id),
      {:feeds_refreshed,
       %{
         user_id: feed.user_id,
         feed_id: feed.id,
         inserted: stats.inserted,
         updated: stats.updated
       }}
    )
  end

  defp log_refresh_success(feed, stats, meta) do
    Logger.info(
      "Feed refresh succeeded feed_id=#{feed.id} url=#{feed.feed_url} status=#{meta_value(meta, :http_status)} bytes=#{meta_value(meta, :bytes)} parsed_items=#{meta_value(meta, :parsed_items)} inserted=#{stats.inserted} updated=#{stats.updated} skipped=#{stats.skipped} duration_ms=#{meta_value(meta, :duration_ms)} reason=#{inspect(meta_value(meta, :halted_reason))}"
    )
  end

  defp log_refresh_error(feed, reason, meta) do
    Logger.warning(
      "Feed refresh failed feed_id=#{feed.id} url=#{feed.feed_url} final_url=#{meta_value(meta, :final_url)} status=#{meta_value(meta, :http_status)} content_type=#{inspect(meta_value(meta, :content_type))} content_length=#{meta_value(meta, :content_length)} bytes=#{meta_value(meta, :bytes)} parsed_items=#{meta_value(meta, :parsed_items)} halted_reason=#{inspect(meta_value(meta, :halted_reason))} partial_halt=#{meta_value(meta, :partial_halt?)} duration_ms=#{meta_value(meta, :duration_ms)} preview_start=#{inspect(meta_value(meta, :preview_start))} preview_current=#{inspect(meta_value(meta, :preview_current))} reason=#{format_refresh_error_reason(reason)}"
    )
  end

  defp emit_refresh_success(feed, stats, meta) do
    duration_ms = meta_value(meta, :duration_ms) || 0

    :telemetry.execute(
      [:icarurss, :reader, :feed_refresh, :stop],
      %{duration: System.convert_time_unit(duration_ms, :millisecond, :native)},
      %{feed_id: feed.id, user_id: feed.user_id, result: :ok, kind: :ok}
    )

    :telemetry.execute(
      [:icarurss, :reader, :feed_refresh, :items],
      %{count: stats.inserted + stats.updated + stats.skipped},
      %{feed_id: feed.id, user_id: feed.user_id, result: :ok}
    )
  end

  defp meta_value(meta, key) when is_map(meta), do: Map.get(meta, key)
  defp meta_value(_meta, _key), do: nil

  defp broadcast_articles_read(user_id) do
    Phoenix.PubSub.broadcast(
      Icarurss.PubSub,
      user_topic(user_id),
      {:articles_read, %{user_id: user_id}}
    )
  end

  defp emit_refresh_error(feed, reason) do
    error_message = format_refresh_error_reason(reason)
    error_kind = refresh_error_kind(reason)
    failure_count = (feed.refresh_failure_count || 0) + 1
    status = if RefreshError.retryable?(reason), do: "transient_error", else: "permanent_error"

    case update_feed(feed, %{
           last_refresh_error: error_message,
           refresh_status: status,
           refresh_error_kind: error_kind,
           refresh_failure_count: failure_count,
           last_refresh_failed_at: DateTime.utc_now(:second),
           next_refresh_after: next_refresh_after(reason, failure_count)
         }) do
      {:ok, updated_feed} ->
        Phoenix.PubSub.broadcast(
          Icarurss.PubSub,
          user_topic(updated_feed.user_id),
          {:feed_refresh_failed,
           %{
             user_id: updated_feed.user_id,
             feed_id: updated_feed.id,
             reason: error_message
           }}
        )

      {:error, changeset} ->
        Logger.error(
          "Could not persist refresh error for feed_id=#{feed.id}: #{inspect(changeset.errors)}"
        )
    end

    :telemetry.execute(
      [:icarurss, :reader, :feed_refresh, :error],
      %{count: 1},
      %{
        feed_id: feed.id,
        user_id: feed.user_id,
        reason: error_message,
        kind: error_kind,
        retryable?: RefreshError.retryable?(reason)
      }
    )

    :telemetry.execute(
      [:icarurss, :reader, :feed_refresh, :stop],
      %{duration: 0},
      %{feed_id: feed.id, user_id: feed.user_id, result: :error, kind: error_kind}
    )
  end

  defp refresh_error_kind(%RefreshError{kind: kind}), do: Atom.to_string(kind)
  defp refresh_error_kind(_reason), do: "request"

  defp next_refresh_after(reason, failure_count) do
    seconds =
      if RefreshError.retryable?(reason) do
        min(:math.pow(2, failure_count) |> trunc(), 60) * 60
      else
        min(:math.pow(2, max(failure_count - 1, 0)) |> trunc(), 7) * 24 * 60 * 60
      end

    DateTime.add(DateTime.utc_now(:second), seconds, :second)
  end

  defp format_refresh_error_reason(reason) when is_binary(reason) do
    String.slice(reason, 0, 500)
  end

  defp format_refresh_error_reason(%RefreshError{} = reason) do
    reason.message
    |> String.slice(0, 500)
  end

  defp format_refresh_error_reason(reason) do
    reason
    |> inspect()
    |> String.slice(0, 500)
  end

  defp refresh_feeds(feeds, initial_mark_read?, max_concurrency) do
    feeds
    |> Task.async_stream(
      fn feed ->
        case refresh_feed(feed, initial_mark_read: initial_mark_read?) do
          {:ok, stats} -> {:ok, stats}
          {:error, _reason} -> :error
        end
      end,
      timeout: :infinity,
      max_concurrency: max_concurrency,
      ordered: false
    )
    |> reduce_refresh_results()
  end

  defp feed_refresh_max_concurrency do
    Application.get_env(:icarurss, :feed_refresh, [])
    |> Keyword.get(:max_concurrency, 1)
  end

  defp feed_source_module do
    Application.get_env(:icarurss, :feed_source, Icarurss.Reader.FeedSource.ReqSource)
  end

  defp refresh_deferred?(%Feed{next_refresh_after: nil}), do: false

  defp refresh_deferred?(%Feed{next_refresh_after: next_refresh_after}) do
    DateTime.compare(next_refresh_after, DateTime.utc_now(:second)) == :gt
  end

  defp normalize_folder_id_for_user(_user, nil), do: nil

  defp normalize_folder_id_for_user(%User{id: user_id}, folder_id) when is_integer(folder_id) do
    exists? =
      Repo.exists?(
        from folder in Folder,
          where: folder.id == ^folder_id and folder.user_id == ^user_id,
          select: 1
      )

    if exists?, do: folder_id, else: nil
  end

  defp normalize_folder_id_for_user(_user, _folder_id), do: nil

  defp map_value(map, atom_key) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key) || Map.get(map, Atom.to_string(atom_key))
  end

  defp ensure_folder_for_import(_user, folder_name, folder_lookup, next_position, stats)
       when not is_binary(folder_name) do
    {nil, folder_lookup, next_position, stats}
  end

  defp ensure_folder_for_import(user, folder_name, folder_lookup, next_position, stats) do
    normalized_folder_name = String.trim(folder_name)

    cond do
      normalized_folder_name == "" ->
        {nil, folder_lookup, next_position, stats}

      folder = Map.get(folder_lookup, normalized_folder_name) ->
        {folder.id, folder_lookup, next_position, stats}

      true ->
        case create_folder(user, %{
               name: normalized_folder_name,
               position: next_position,
               expanded: true
             }) do
          {:ok, folder} ->
            {folder.id, Map.put(folder_lookup, folder.name, folder), next_position + 1,
             %{stats | folders_created: stats.folders_created + 1}}

          {:error, _changeset} ->
            existing_folder =
              Enum.find(list_folders(user), fn folder ->
                folder.name == normalized_folder_name
              end)

            case existing_folder do
              %Folder{} = folder ->
                {folder.id, Map.put(folder_lookup, folder.name, folder), next_position, stats}

              nil ->
                {nil, folder_lookup, next_position, stats}
            end
        end
    end
  end

  defp next_folder_position([]), do: 0

  defp next_folder_position(folders) do
    folders
    |> Enum.map(& &1.position)
    |> Enum.max()
    |> Kernel.+(1)
  end

  defp origin_url(nil), do: nil

  defp origin_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        "#{scheme}://#{host}"

      _ ->
        nil
    end
  end

  defp favicon_url_for(nil), do: nil
  defp favicon_url_for(origin), do: origin <> "/favicon.ico"

  defp queue_initial_feed_refreshes(feeds) do
    Enum.reduce(feeds, %{refreshes_queued: 0, refreshes_failed: 0}, fn feed, stats ->
      case %{feed_id: feed.id} |> RefreshFeedWorker.new() |> Oban.insert() do
        {:ok, _job} ->
          %{stats | refreshes_queued: stats.refreshes_queued + 1}

        {:error, reason} ->
          Logger.error(
            "Could not enqueue initial refresh for imported feed_id=#{feed.id}: #{inspect(reason)}"
          )

          %{stats | refreshes_failed: stats.refreshes_failed + 1}
      end
    end)
  end
end
