# TODOS.md Plan: Icarurss v1 (Phoenix + LiveView)

## Summary
Build a self-hosted, multi-user RSS reader with a LiveView 3-column UI, email magic-link auth, invite-first onboarding, SQLite storage, background polling, and live article updates.  
Use layout-first parity with your mockup (structure/interactions first, visual polish second).

## Public APIs / Interfaces / Types
- Runtime env:
  - `REGISTRATION_ENABLED` (default `false`).
  - `FEED_POLL_INTERVAL_MINUTES` (default `10`).
  - mailer/smtp envs for invite/login links in non-dev.
- CLI:
  - `mix users.new` interactive task (email + role `admin|member`, sends invite/login link).
- Auth:
  - `phx.gen.auth` LiveView flow, email magic-link only.
- Core route:
  - `/` => Reader LiveView (3-column app shell).
- Data model (v1 decision):
  - Fully isolated per user (`users` own their `folders`, `feeds`, `articles`).
  - Roles enum: `admin | member`.
  - No username in v1.
- Search contract:
  - Prefer SQLite FTS5.
  - Fallback to `LIKE` if FTS setup is blocked.

## TODO Checklist

### 1) Foundation and Auth
- [x] Add auth scaffolding with LiveView (`mix phx.gen.auth ... --live`) and keep email magic-link login flow only.
- [x] Add `role` enum (`admin|member`) to user schema and migration.
- [x] Add runtime config flag `REGISTRATION_ENABLED` with default `false`.
- [x] Enforce registration gating: when disabled, only existing users can request login links.
- [x] Keep invite/email flows functional in dev mailbox and configurable SMTP for prod (email is not the login identifier).

### 2) User Bootstrap and Access
- [x] Create `mix users.new` interactive task for creating/inviting users and setting role.
- [x] Restrict user-management operations to `admin` role checks (CLI + future web hooks).
- [x] Add clear error messages for non-admin management attempts.

### 3) Database Schema (Isolated Per User)
- [x] Create `folders` table: `user_id`, `name`, `position`, `expanded` (default true), timestamps.
- [x] Create `feeds` table: `user_id`, nullable `folder_id`, `title`, `site_url`, `feed_url`, `base_url`, `favicon_url`, `last_fetched_at`, timestamps.
- [x] Create `articles` table: `user_id`, `feed_id`, `guid`, `url`, `title`, `author`, `summary_html`, `content_html`, `published_at`, `fetched_at`, `is_read`, `is_starred`, timestamps.
- [x] Add unique constraints/indexes for dedupe and query speed (notably per-user feed/article uniqueness and unread/starred filters).
- [x] Ensure folder membership is one-level only and feed belongs to at most one folder.

### 4) Feed Discovery and Subscription
- [x] Implement add-feed modal workflow in LiveView.
- [x] Accept website URL input and discover candidate feeds from HTML (`<link rel="alternate"...>`).
- [x] Fetch/parse candidate feed URLs and show picker UI when multiple feeds found.
- [x] On subscribe, create feed for current user and backfill initial items as `is_read=true`.
- [x] Handle invalid URLs, unreachable pages, and no-feed-found states gracefully.

### 5) RSS/Atom Fetch + Parse Pipeline
- [x] Implement feed fetcher service using `Req`.
- [x] Parse RSS/Atom items with robust best-effort field extraction.
- [x] `published_at` logic: prefer item published date, fallback to updated date, fallback to fetch time.
- [x] Normalize and sanitize item HTML before persistence.
- [x] Cache favicon best-effort per feed with placeholder fallback.
- [x] Dedupe items per feed/user using stable key strategy (`guid` then URL/title fallback).

### 6) Background Jobs and Scheduling
- [x] Add Oban and configure queue(s) + cron for global feed polling every 10 minutes.
- [x] Add manual “Refresh All” action to enqueue immediate refresh jobs.
- [x] Add retry/backoff policy and error telemetry for failed feed fetches.
- [ ] Keep per-feed custom polling interval explicitly out of v1 scope.

### 7) Reader LiveView (3-Column + Top Navbar)
- [x] Replace default homepage with Reader LiveView wrapped in `<Layouts.app ...>`.
- [x] Build top navbar actions: Add Feed, Refresh All, centered search input, Mark All Read.
- [x] Implement left column (ratio target 1): `Unread`, `All`, `Starred`, folders (expand/collapse), ungrouped feeds.
- [x] Implement second column (ratio target 2): article rows with favicon, title, date, feed/site label, unread indicator.
- [x] Implement third column (ratio target 4): feed name left, favicon right, title, `published_at`, content.
- [x] Clicking feed/folder filters column 2 to read+unread items.
- [x] Clicking article auto-marks read and loads full pane.
- [x] “Mark All Read” affects exactly the currently displayed article scope in column 2.
- [x] New incoming items prepend in column 2 with subtle highlight while preserving current selected article.

### 8) Feed/Folder Management
- [x] Folder CRUD (create, rename, delete) in LiveView.
- [x] Move feeds between folders and to ungrouped root.
- [x] Unsubscribe feed flow with confirmation.
- [x] Keep folder expansion state persisted per user.

### 9) Search
- [x] Implement search across title/content/feed title/base URL.
- [x] Prefer SQLite FTS5 virtual table/index and ranking.
- [x] Implement fallback `LIKE` query path if FTS5 is unavailable.
- [x] Ensure search integrates with current scope/filter and updates column 2 list.

### 10) OPML Portability (v1 included)
- [x] Add OPML import parser to create folders + feeds for current user.
- [x] Add OPML export generator for user subscriptions/folder structure.
- [x] Validate malformed OPML handling and duplicate feed import behavior.

### 11) UX/Polish
- [ ] Match attached mockup structure and interaction model (layout-first parity).
- [ ] Add subtle micro-interactions: hover states, unread badge transitions, refresh/loading states.
- [ ] Ensure responsive behavior for smaller screens (progressive collapse strategy).
- [ ] Keep typography/spacing consistent and readable for long-form article content.

### 12) Testing and Acceptance
- [x] Context tests: subscriptions, dedupe, read/star toggles, folder operations, search queries, OPML import/export.
- [x] LiveView tests: key element IDs, add-feed modal flow, filter switching, mark-all-read behavior, article open auto-read.
- [x] Job tests: scheduled polling enqueues, manual refresh enqueues, retry/error behavior.
- [x] Auth/access tests: registration disabled behavior, invite/login link flow, role restrictions.
- [ ] End-to-end acceptance pass: multi-user isolation (one user’s feeds/articles/states never appear for another).

## Explicit Assumptions and Defaults
- Auth is email magic-link only for v1 (no username, no password login).
- Registration is closed by default (`REGISTRATION_ENABLED=false`).
- Data is fully isolated per user (no shared article/feed rows across users).
- Global polling interval is 10 minutes; per-feed interval is deferred.
- Initial backfill on new subscription is marked read.
- Article content source is RSS/Atom item content/summary only (no webpage readability fetch in v1).
- UI target is layout/interaction parity with provided reference, not pixel-perfect clone.
