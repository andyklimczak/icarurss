defmodule IcarurssWeb.ReaderLive do
  use IcarurssWeb, :live_view

  alias Icarurss.Reader
  alias Icarurss.Workers.RefreshAllFeedsWorker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Icarurss.PubSub, Reader.user_topic(user.id))
    end

    socket =
      socket
      |> assign(:filter, :unread)
      |> assign(:selected_feed_id, nil)
      |> assign(:selected_feed, nil)
      |> assign(:selected_folder_id, nil)
      |> assign(:selected_article_id, nil)
      |> assign(:selected_article, nil)
      |> assign(:new_folder_form, to_form(%{"name" => ""}, as: :new_folder))
      |> assign(:editing_folder_id, nil)
      |> assign(:edit_folder_form, to_form(%{"name" => ""}, as: :edit_folder))
      |> assign(:confirm_delete_folder_id, nil)
      |> assign(:move_feed_form, to_form(%{"folder_id" => ""}, as: :move_feed))
      |> assign(:confirm_unsubscribe_feed_id, nil)
      |> assign(:search_form, to_form(%{"q" => ""}, as: :search))
      |> assign(:show_add_feed_modal, false)
      |> assign(:add_feed_form, to_form(%{"url" => ""}, as: :add_feed))
      |> assign(:add_feed_candidates, [])
      |> assign(:discovering_feeds, false)
      |> assign(:adding_feed, false)
      |> assign(:articles_count, 0)
      |> assign(:highlight_article_ids, MapSet.new())
      |> assign(:article_ids_in_view, [])
      |> stream(:articles, [])
      |> load_sidebar(user)
      |> load_articles(user)

    {:ok, socket}
  end

  @impl true
  def handle_info({:feeds_refreshed, %{user_id: user_id}}, socket) do
    user = socket.assigns.current_scope.user

    if user.id == user_id do
      socket =
        socket
        |> load_sidebar(user)
        |> load_articles(user, preserve_selected: true, highlight_new: true)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:clear_article_highlights, socket) do
    {:noreply, assign(socket, :highlight_article_ids, MapSet.new())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="h-[calc(100vh-8rem)] overflow-hidden rounded-xl border border-zinc-200 bg-white shadow-sm">
        <div class="border-b border-zinc-200 px-4 py-2">
          <div class="grid grid-cols-1 gap-2 md:grid-cols-[1fr_2fr_1fr] md:items-center">
            <div class="flex items-center gap-2">
              <button
                id="add-feed-button"
                type="button"
                phx-click="open_add_feed"
                class="inline-flex items-center rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
              >
                <.icon name="hero-plus" class="mr-1 size-4" /> Add Feed
              </button>
              <button
                id="refresh-feeds-button"
                type="button"
                phx-click="refresh_feeds"
                class="inline-flex items-center rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
              >
                <.icon name="hero-arrow-path" class="mr-1 size-4" /> Refresh
              </button>
            </div>

            <.form
              for={@search_form}
              id="reader-search-form"
              phx-change="search"
              phx-submit="search"
              class="w-full"
            >
              <.input
                id="reader-search-input"
                field={@search_form[:q]}
                type="text"
                placeholder="Search title, content, feed, url..."
                class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
                label="Search"
              />
            </.form>

            <div class="flex justify-start md:justify-end">
              <button
                id="mark-visible-read-button"
                type="button"
                phx-click="mark_all_read"
                class="inline-flex items-center rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
              >
                <.icon name="hero-check" class="mr-1 size-4" /> Mark All Read
              </button>
            </div>
          </div>
        </div>

        <div class="grid h-[calc(100%-3.2rem)] grid-cols-1 overflow-hidden lg:grid-cols-[1fr_2fr_4fr]">
          <aside class="h-full overflow-y-auto border-b border-zinc-200 bg-zinc-50 p-3 lg:border-b-0 lg:border-r">
            <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-zinc-500">
              Smart Feeds
            </h2>

            <.form for={@new_folder_form} id="new-folder-form" phx-submit="create_folder">
              <.input
                id="new-folder-name"
                field={@new_folder_form[:name]}
                type="text"
                label="New Folder"
                placeholder="Add a folder"
                class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
              />
            </.form>

            <div class="space-y-1">
              <button
                id="sidebar-filter-unread"
                type="button"
                phx-click="select_filter"
                phx-value-filter="unread"
                class={
                  sidebar_item_class(
                    @filter == :unread and is_nil(@selected_feed_id) and is_nil(@selected_folder_id)
                  )
                }
              >
                <span>Unread</span>
                <span class="rounded-full bg-zinc-200 px-2 py-0.5 text-xs">{@unread_count}</span>
              </button>

              <button
                id="sidebar-filter-all"
                type="button"
                phx-click="select_filter"
                phx-value-filter="all"
                class={
                  sidebar_item_class(
                    @filter == :all and is_nil(@selected_feed_id) and is_nil(@selected_folder_id)
                  )
                }
              >
                <span>All</span>
              </button>

              <button
                id="sidebar-filter-starred"
                type="button"
                phx-click="select_filter"
                phx-value-filter="starred"
                class={
                  sidebar_item_class(
                    @filter == :starred and is_nil(@selected_feed_id) and is_nil(@selected_folder_id)
                  )
                }
              >
                <span>Starred</span>
              </button>
            </div>

            <div class="mt-4 space-y-1">
              <%= for feed <- @ungrouped_feeds do %>
                <button
                  type="button"
                  id={"sidebar-feed-#{feed.id}"}
                  phx-click="select_feed"
                  phx-value-id={feed.id}
                  class={sidebar_item_class(@selected_feed_id == feed.id)}
                >
                  <span class="truncate">{feed.title || feed.feed_url}</span>
                  <span
                    :if={Map.get(@feed_unread_counts, feed.id, 0) > 0}
                    class="rounded-full bg-zinc-200 px-2 py-0.5 text-xs"
                  >
                    {Map.get(@feed_unread_counts, feed.id)}
                  </span>
                </button>
              <% end %>
            </div>

            <div class="mt-4 space-y-2">
              <%= for folder <- @folders do %>
                <div id={"folder-#{folder.id}"} class="rounded-md border border-zinc-200 bg-white">
                  <div :if={@editing_folder_id == folder.id} class="p-2">
                    <.form
                      for={@edit_folder_form}
                      id={"edit-folder-form-#{folder.id}"}
                      phx-submit="rename_folder"
                    >
                      <input type="hidden" name="edit_folder[id]" value={folder.id} />
                      <.input
                        field={@edit_folder_form[:name]}
                        type="text"
                        label="Rename Folder"
                        required
                        class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
                      />
                      <div class="flex gap-2">
                        <button
                          type="submit"
                          class="inline-flex items-center rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_rename_folder"
                          class="inline-flex items-center rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
                        >
                          Cancel
                        </button>
                      </div>
                    </.form>
                  </div>

                  <div
                    :if={@editing_folder_id != folder.id}
                    class="flex items-center justify-between p-1"
                  >
                    <button
                      type="button"
                      id={"sidebar-folder-#{folder.id}"}
                      phx-click="select_folder"
                      phx-value-id={folder.id}
                      class={sidebar_item_class(@selected_folder_id == folder.id)}
                    >
                      <span class="truncate">{folder.name}</span>
                    </button>
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        id={"rename-folder-#{folder.id}"}
                        phx-click="start_rename_folder"
                        phx-value-id={folder.id}
                        class="rounded p-1 text-zinc-500 transition hover:bg-zinc-100 hover:text-zinc-700"
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                      </button>
                      <button
                        type="button"
                        id={"delete-folder-#{folder.id}"}
                        phx-click="delete_folder"
                        phx-value-id={folder.id}
                        class={[
                          "rounded p-1 transition",
                          @confirm_delete_folder_id == folder.id &&
                            "bg-red-100 text-red-700 hover:bg-red-200",
                          @confirm_delete_folder_id != folder.id &&
                            "text-zinc-500 hover:bg-zinc-100 hover:text-zinc-700"
                        ]}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                      <button
                        type="button"
                        id={"toggle-folder-#{folder.id}"}
                        phx-click="toggle_folder"
                        phx-value-id={folder.id}
                        class="rounded p-1 text-zinc-500 transition hover:bg-zinc-100 hover:text-zinc-700"
                      >
                        <.icon
                          name={
                            if folder.expanded, do: "hero-chevron-down", else: "hero-chevron-right"
                          }
                          class="size-4"
                        />
                      </button>
                    </div>
                  </div>
                  <div :if={folder.expanded} class="space-y-1 px-1 pb-1">
                    <%= for feed <- folder.feeds do %>
                      <button
                        type="button"
                        id={"sidebar-feed-#{feed.id}"}
                        phx-click="select_feed"
                        phx-value-id={feed.id}
                        class={sidebar_item_class(@selected_feed_id == feed.id)}
                      >
                        <span class="truncate">{feed.title || feed.feed_url}</span>
                        <span
                          :if={Map.get(@feed_unread_counts, feed.id, 0) > 0}
                          class="rounded-full bg-zinc-200 px-2 py-0.5 text-xs"
                        >
                          {Map.get(@feed_unread_counts, feed.id)}
                        </span>
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </aside>

          <section class="h-full overflow-y-auto border-b border-zinc-200 bg-zinc-100 lg:border-b-0 lg:border-r">
            <div class="border-b border-zinc-200 bg-zinc-50 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-zinc-500">
              Articles ({@articles_count})
            </div>

            <div
              :if={@selected_feed_id && @selected_feed}
              id="selected-feed-actions"
              class="flex flex-wrap items-center gap-2 border-b border-zinc-200 bg-zinc-50 px-3 py-2"
            >
              <.form for={@move_feed_form} id="move-feed-form" phx-change="move_feed" class="min-w-52">
                <input type="hidden" name="move_feed[feed_id]" value={@selected_feed_id} />
                <.input
                  field={@move_feed_form[:folder_id]}
                  type="select"
                  options={folder_options(@folders)}
                  prompt="Ungrouped"
                  label="Folder"
                  class="w-full rounded-md border border-zinc-300 px-2 py-1 text-sm"
                />
              </.form>

              <button
                id="unsubscribe-feed-button"
                type="button"
                phx-click="unsubscribe_feed"
                phx-value-id={@selected_feed_id}
                class={[
                  "inline-flex items-center rounded-md border px-3 py-1.5 text-sm transition",
                  @confirm_unsubscribe_feed_id == @selected_feed_id &&
                    "border-red-300 bg-red-100 text-red-700 hover:bg-red-200",
                  @confirm_unsubscribe_feed_id != @selected_feed_id &&
                    "border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-100"
                ]}
              >
                <.icon name="hero-trash" class="mr-1 size-4" />
                {if @confirm_unsubscribe_feed_id == @selected_feed_id,
                  do: "Confirm Unsubscribe",
                  else: "Unsubscribe"}
              </button>
            </div>

            <div id="articles" phx-update="stream" class="divide-y divide-zinc-200">
              <div id="articles-empty-state" class="hidden p-4 text-sm text-zinc-500 only:block">
                No articles found.
              </div>
              <button
                :for={{dom_id, article} <- @streams.articles}
                id={dom_id}
                type="button"
                phx-click="select_article"
                phx-value-id={article.id}
                class={[
                  "w-full p-3 text-left transition hover:bg-zinc-200/60",
                  MapSet.member?(@highlight_article_ids, article.id) && "bg-emerald-50",
                  @selected_article_id == article.id && "bg-zinc-200"
                ]}
              >
                <div class="flex items-start gap-3">
                  <%= if article.feed.favicon_url do %>
                    <img src={article.feed.favicon_url} alt="" class="mt-1 size-5 rounded" />
                  <% else %>
                    <span class="mt-1 rounded bg-zinc-300 p-1 text-zinc-600">
                      <.icon name="hero-rss" class="size-3" />
                    </span>
                  <% end %>
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                      <span
                        :if={!article.is_read}
                        class="inline-block size-2 rounded-full bg-blue-500"
                      >
                      </span>
                      <p class="truncate text-sm font-medium text-zinc-900">{article.title}</p>
                    </div>
                    <p class="mt-1 text-xs text-zinc-500">
                      {format_datetime(article.published_at || article.inserted_at)}
                    </p>
                    <p class="text-xs text-zinc-500">
                      {article.feed.title || article.feed.base_url || article.feed.site_url}
                    </p>
                  </div>
                </div>
              </button>
            </div>
          </section>

          <section id="article-reader" class="h-full overflow-y-auto bg-white p-6">
            <%= if @selected_article do %>
              <div class="mb-4 flex items-center justify-between text-sm text-zinc-600">
                <span>{@selected_article.feed.title || @selected_article.feed.base_url}</span>
                <%= if @selected_article.feed.favicon_url do %>
                  <img src={@selected_article.feed.favicon_url} alt="" class="size-5 rounded" />
                <% else %>
                  <span class="rounded bg-zinc-100 p-1 text-zinc-600">
                    <.icon name="hero-rss" class="size-3" />
                  </span>
                <% end %>
              </div>

              <h1 class="text-3xl font-semibold tracking-tight text-zinc-900">
                {@selected_article.title}
              </h1>

              <p class="mt-3 text-sm text-zinc-500">
                Published {format_datetime(
                  @selected_article.published_at || @selected_article.inserted_at
                )}
              </p>

              <button
                id="toggle-star-button"
                type="button"
                phx-click="toggle_star"
                phx-value-id={@selected_article.id}
                class="mt-4 inline-flex items-center rounded-md border border-zinc-300 px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
              >
                <.icon
                  name={if @selected_article.is_starred, do: "hero-star-solid", else: "hero-star"}
                  class="mr-1 size-4"
                />
                {if @selected_article.is_starred, do: "Starred", else: "Star"}
              </button>

              <article id="article-content" class="prose prose-zinc mt-6 max-w-none">
                {raw(@selected_article.content_html || @selected_article.summary_html || "")}
              </article>
            <% else %>
              <div class="grid h-full place-items-center text-zinc-400">
                <div class="text-center">
                  <.icon name="hero-newspaper" class="mx-auto size-10" />
                  <p class="mt-2 text-sm">Select an article to read</p>
                </div>
              </div>
            <% end %>
          </section>
        </div>
      </div>

      <%= if @show_add_feed_modal do %>
        <div id="add-feed-modal" class="fixed inset-0 z-40 flex items-center justify-center p-4">
          <div
            class="absolute inset-0 bg-zinc-900/40"
            phx-click="close_add_feed"
            aria-hidden="true"
          >
          </div>

          <div class="relative z-50 w-full max-w-2xl rounded-xl border border-zinc-200 bg-white shadow-xl">
            <div class="flex items-center justify-between border-b border-zinc-200 px-5 py-4">
              <h2 class="text-base font-semibold text-zinc-900">Add Feed</h2>
              <button
                id="close-add-feed-modal"
                type="button"
                phx-click="close_add_feed"
                class="rounded p-1 text-zinc-500 transition hover:bg-zinc-100 hover:text-zinc-700"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div class="space-y-4 p-5">
              <.form for={@add_feed_form} id="discover-feeds-form" phx-submit="discover_feeds">
                <.input
                  id="discover-feeds-url"
                  field={@add_feed_form[:url]}
                  type="url"
                  label="Website or feed URL"
                  placeholder="https://example.com"
                  required
                  class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
                />
                <.button
                  id="discover-feeds-button"
                  class="w-full"
                  disabled={@discovering_feeds}
                  phx-disable-with="Discovering..."
                >
                  Discover feeds
                </.button>
              </.form>

              <div id="feed-candidates" class="space-y-2">
                <%= for {candidate, index} <- Enum.with_index(@add_feed_candidates) do %>
                  <div
                    id={"feed-candidate-#{index}"}
                    class="flex items-center justify-between rounded-lg border border-zinc-200 px-3 py-2"
                  >
                    <div class="min-w-0 pr-3">
                      <p class="truncate text-sm font-medium text-zinc-900">
                        {candidate.title || candidate.feed_url}
                      </p>
                      <p class="truncate text-xs text-zinc-500">{candidate.feed_url}</p>
                    </div>
                    <button
                      id={"subscribe-feed-#{index}"}
                      type="button"
                      phx-click="subscribe_feed"
                      phx-value-index={index}
                      class="inline-flex items-center rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100"
                    >
                      Add
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("open_add_feed", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_feed_modal, true)
     |> assign(:add_feed_form, to_form(%{"url" => ""}, as: :add_feed))
     |> assign(:add_feed_candidates, [])
     |> assign(:discovering_feeds, false)
     |> assign(:adding_feed, false)}
  end

  @impl true
  def handle_event("close_add_feed", _params, socket) do
    {:noreply, close_add_feed_modal(socket)}
  end

  @impl true
  def handle_event("discover_feeds", %{"add_feed" => %{"url" => raw_url}}, socket) do
    url = String.trim(raw_url)
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:discovering_feeds, true)
      |> assign(:add_feed_candidates, [])
      |> assign(:add_feed_form, to_form(%{"url" => url}, as: :add_feed))

    case Reader.discover_feed_candidates(url) do
      {:ok, candidates} ->
        {:noreply,
         socket
         |> assign(:discovering_feeds, false)
         |> assign(:add_feed_candidates, candidates)
         |> load_sidebar(user)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:discovering_feeds, false)
         |> assign(:add_feed_candidates, [])
         |> put_flash(:error, reason)}
    end
  end

  @impl true
  def handle_event("subscribe_feed", %{"index" => index}, socket) do
    user = socket.assigns.current_scope.user
    candidate = Enum.at(socket.assigns.add_feed_candidates, parse_id(index))

    if candidate do
      case Reader.subscribe_feed_from_candidate(user, candidate, initial_mark_read: true) do
        {:ok, feed, {:ok, stats}} ->
          socket =
            socket
            |> close_add_feed_modal()
            |> assign(:filter, :all)
            |> assign(:selected_feed_id, feed.id)
            |> assign(:selected_folder_id, nil)
            |> assign_selected_feed(feed)
            |> load_sidebar(user)
            |> load_articles(user)
            |> put_flash(:info, "Feed added. Imported #{stats.inserted} articles.")

          {:noreply, socket}

        {:ok, feed, {:error, reason}} ->
          socket =
            socket
            |> close_add_feed_modal()
            |> assign(:filter, :all)
            |> assign(:selected_feed_id, feed.id)
            |> assign(:selected_folder_id, nil)
            |> assign_selected_feed(feed)
            |> load_sidebar(user)
            |> load_articles(user)
            |> put_flash(:error, "Feed added, but initial fetch failed: #{reason}")

          {:noreply, socket}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, put_flash(socket, :error, "Could not add feed. It may already exist.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_feeds", _params, socket) do
    case RefreshAllFeedsWorker.new(%{}) |> Oban.insert() do
      {:ok, _job} ->
        {:noreply,
         put_flash(socket, :info, "Feed refresh queued. New articles will appear automatically.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not queue feed refresh job.")}
    end
  end

  @impl true
  def handle_event("select_filter", %{"filter" => filter}, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:filter, parse_filter(filter))
      |> assign(:selected_feed_id, nil)
      |> assign_selected_feed(nil)
      |> assign(:selected_folder_id, nil)
      |> assign(:selected_article_id, nil)
      |> assign(:selected_article, nil)
      |> load_articles(user)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_feed", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    feed = Reader.get_feed_for_user!(user, parse_id(id))

    socket =
      socket
      |> assign(:filter, :all)
      |> assign(:selected_feed_id, feed.id)
      |> assign_selected_feed(feed)
      |> assign(:selected_folder_id, nil)
      |> assign(:selected_article_id, nil)
      |> assign(:selected_article, nil)
      |> load_articles(user)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_folder", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:filter, :all)
      |> assign(:selected_folder_id, parse_id(id))
      |> assign(:selected_feed_id, nil)
      |> assign_selected_feed(nil)
      |> assign(:selected_article_id, nil)
      |> assign(:selected_article, nil)
      |> load_articles(user)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_folder", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    folder = Enum.find(socket.assigns.folders, &(&1.id == parse_id(id)))

    socket =
      if folder do
        {:ok, _folder} = Reader.update_folder(folder, %{expanded: !folder.expanded})
        load_sidebar(socket, user)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_folder", %{"new_folder" => %{"name" => name}}, socket) do
    user = socket.assigns.current_scope.user

    case Reader.create_folder(user, %{
           name: name,
           position: next_folder_position(socket.assigns.folders)
         }) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> assign(:new_folder_form, to_form(%{"name" => ""}, as: :new_folder))
         |> load_sidebar(user)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create folder.")}
    end
  end

  @impl true
  def handle_event("start_rename_folder", %{"id" => id}, socket) do
    folder = Enum.find(socket.assigns.folders, &(&1.id == parse_id(id)))

    if folder do
      {:noreply,
       socket
       |> assign(:editing_folder_id, folder.id)
       |> assign(:edit_folder_form, to_form(%{"name" => folder.name}, as: :edit_folder))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_rename_folder", _params, socket) do
    {:noreply, assign(socket, :editing_folder_id, nil)}
  end

  @impl true
  def handle_event("rename_folder", %{"edit_folder" => %{"id" => id, "name" => name}}, socket) do
    user = socket.assigns.current_scope.user
    folder = Enum.find(socket.assigns.folders, &(&1.id == parse_id(id)))

    if folder do
      case Reader.update_folder(folder, %{name: name}) do
        {:ok, _folder} ->
          {:noreply,
           socket
           |> assign(:editing_folder_id, nil)
           |> load_sidebar(user)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not rename folder.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_folder", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    folder_id = parse_id(id)

    if socket.assigns.confirm_delete_folder_id == folder_id do
      folder = Enum.find(socket.assigns.folders, &(&1.id == folder_id))

      if folder do
        {:ok, _folder} = Reader.delete_folder(folder)

        socket =
          socket
          |> assign(:confirm_delete_folder_id, nil)
          |> assign(:selected_folder_id, nil)
          |> load_sidebar(user)
          |> load_articles(user)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :confirm_delete_folder_id, folder_id)}
    end
  end

  @impl true
  def handle_event(
        "move_feed",
        %{"move_feed" => %{"feed_id" => feed_id, "folder_id" => folder_id}},
        socket
      ) do
    user = socket.assigns.current_scope.user
    feed = Reader.get_feed_for_user!(user, parse_id(feed_id))
    target_folder_id = parse_optional_id(folder_id)

    case Reader.update_feed(feed, %{folder_id: target_folder_id}) do
      {:ok, updated_feed} ->
        socket =
          socket
          |> assign_selected_feed(updated_feed)
          |> load_sidebar(user)
          |> load_articles(user, preserve_selected: true)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not move feed.")}
    end
  end

  @impl true
  def handle_event("unsubscribe_feed", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    feed_id = parse_id(id)

    if socket.assigns.confirm_unsubscribe_feed_id == feed_id do
      feed = Reader.get_feed_for_user!(user, feed_id)
      {:ok, _feed} = Reader.delete_feed(feed)

      socket =
        socket
        |> assign(:selected_feed_id, nil)
        |> assign_selected_feed(nil)
        |> assign(:selected_article_id, nil)
        |> assign(:selected_article, nil)
        |> assign(:confirm_unsubscribe_feed_id, nil)
        |> load_sidebar(user)
        |> load_articles(user)
        |> put_flash(:info, "Feed unsubscribed.")

      {:noreply, socket}
    else
      {:noreply, assign(socket, :confirm_unsubscribe_feed_id, feed_id)}
    end
  end

  @impl true
  def handle_event("select_article", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    article = Reader.get_article_for_user!(user, parse_id(id))

    article =
      if article.is_read do
        article
      else
        {:ok, updated_article} = Reader.mark_article_read(article)
        updated_article
      end

    socket =
      socket
      |> assign(:selected_article_id, article.id)
      |> assign(:selected_article, article)
      |> load_sidebar(user)
      |> load_articles(user, preserve_selected: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_star", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    article = Reader.get_article_for_user!(user, parse_id(id))
    {:ok, updated_article} = Reader.mark_article_starred(article, !article.is_starred)

    socket =
      socket
      |> assign(:selected_article, updated_article)
      |> load_sidebar(user)
      |> load_articles(user, preserve_selected: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    user = socket.assigns.current_scope.user
    _count = Reader.mark_all_read_for_user(user, reader_scope_opts(socket.assigns))

    socket =
      socket
      |> load_sidebar(user)
      |> load_articles(user, preserve_selected: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => %{"q" => query}}, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:search_form, to_form(%{"q" => query}, as: :search))
      |> load_articles(user)

    {:noreply, socket}
  end

  defp load_sidebar(socket, user) do
    socket
    |> assign(:folders, Reader.list_folders_with_feeds(user))
    |> assign(:ungrouped_feeds, Reader.list_ungrouped_feeds(user))
    |> assign(:feed_unread_counts, Reader.feed_unread_counts(user))
    |> assign(:unread_count, Reader.unread_count_for_user(user))
  end

  defp load_articles(socket, user, opts \\ []) do
    preserve_selected? = Keyword.get(opts, :preserve_selected, false)
    highlight_new? = Keyword.get(opts, :highlight_new, false)
    articles = Reader.list_articles_for_user(user, reader_scope_opts(socket.assigns))
    article_ids = Enum.map(articles, & &1.id)

    previous_ids =
      socket.assigns
      |> Map.get(:article_ids_in_view, [])
      |> MapSet.new()

    highlight_article_ids =
      if highlight_new? do
        article_ids
        |> MapSet.new()
        |> MapSet.difference(previous_ids)
      else
        MapSet.new()
      end

    selected_article =
      case {socket.assigns.selected_article_id, preserve_selected?} do
        {nil, _} ->
          nil

        {selected_id, _} ->
          Enum.find(articles, &(&1.id == selected_id)) ||
            if(preserve_selected?, do: socket.assigns.selected_article)
      end

    socket =
      socket
      |> assign(:articles_count, length(articles))
      |> assign(:selected_article, selected_article)
      |> assign(:article_ids_in_view, article_ids)
      |> assign(:highlight_article_ids, highlight_article_ids)
      |> stream(:articles, articles, reset: true)

    if MapSet.size(highlight_article_ids) > 0 do
      Process.send_after(self(), :clear_article_highlights, 2_500)
      socket
    else
      socket
    end
  end

  defp reader_scope_opts(assigns) do
    opts = [filter: assigns.filter, search: assigns.search_form.params["q"] || ""]

    opts =
      if is_integer(assigns.selected_feed_id) do
        Keyword.put(opts, :feed_id, assigns.selected_feed_id)
      else
        opts
      end

    if is_integer(assigns.selected_folder_id) do
      Keyword.put(opts, :folder_id, assigns.selected_folder_id)
    else
      opts
    end
  end

  defp parse_filter("unread"), do: :unread
  defp parse_filter("starred"), do: :starred
  defp parse_filter(_), do: :all

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  defp parse_optional_id(nil), do: nil
  defp parse_optional_id(""), do: nil
  defp parse_optional_id(id), do: parse_id(id)

  defp sidebar_item_class(active?) do
    [
      "flex w-full items-center justify-between rounded-md px-2 py-1.5 text-left text-sm transition",
      if(active?,
        do: "bg-zinc-200 text-zinc-900",
        else: "text-zinc-700 hover:bg-zinc-100 hover:text-zinc-900"
      )
    ]
  end

  defp format_datetime(nil), do: "Unknown date"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y %-I:%M %p")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_datetime()
  end

  defp close_add_feed_modal(socket) do
    socket
    |> assign(:show_add_feed_modal, false)
    |> assign(:add_feed_candidates, [])
    |> assign(:discovering_feeds, false)
    |> assign(:adding_feed, false)
  end

  defp next_folder_position(folders) do
    case folders do
      [] ->
        0

      _ ->
        folders
        |> Enum.map(& &1.position)
        |> Enum.max()
        |> Kernel.+(1)
    end
  end

  defp folder_options(folders) do
    Enum.map(folders, fn folder -> {folder.name, folder.id} end)
  end

  defp assign_selected_feed(socket, nil) do
    socket
    |> assign(:selected_feed, nil)
    |> assign(:move_feed_form, to_form(%{"folder_id" => ""}, as: :move_feed))
    |> assign(:confirm_unsubscribe_feed_id, nil)
  end

  defp assign_selected_feed(socket, feed) do
    folder_id = feed.folder_id || ""

    socket
    |> assign(:selected_feed, feed)
    |> assign(:move_feed_form, to_form(%{"folder_id" => folder_id}, as: :move_feed))
    |> assign(:confirm_unsubscribe_feed_id, nil)
  end
end
