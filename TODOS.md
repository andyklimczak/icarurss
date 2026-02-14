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
- [ ] Add auth scaffolding with LiveView (`mix phx.gen.auth ... --live`) and keep email magic-link login flow only.
- [ ] Add `role` enum (`admin|member`) to user schema and migration.
- [ ] Add runtime config flag `REGISTRATION_ENABLED` with default `false`.
- [ ] Enforce registration gating: when disabled, only existing users can request login links.
- [ ] Keep invite/login mail flows functional in dev mailbox and configurable SMTP for prod.

### 2) User Bootstrap and Access
- [ ] Create `mix users.new` interactive task for creating/inviting users and setting role.
- [ ] Restrict user-management operations to `admin` role checks (CLI + future web hooks).
- [ ] Add clear error messages for non-admin management attempts.

### 3) Database Schema (Isolated Per User)
- [ ] Create `folders` table: `user_id`, `name`, `position`, `expanded` (default true), timestamps.
- [ ] Create `feeds` table: `user_id`, nullable `folder_id`, `title`, `site_url`, `feed_url`, `base_url`, `favicon_url`, `last_fetched_at`, timestamps.
- [ ] Create `articles` table: `user_id`, `feed_id`, `guid`, `url`, `title`, `author`, `summary_html`, `content_html`, `published_at`, `fetched_at`, `is_read`, `is_starred`, timestamps.
- [ ] Add unique constraints/indexes for dedupe and query speed (notably per-user feed/article uniqueness and unread/starred filters).
- [ ] Ensure folder membership is one-level only and feed belongs to at most one folder.

### 4) Feed Discovery and Subscription
- [ ] Implement add-feed modal workflow in LiveView.
- [ ] Accept website URL input and discover candidate feeds from HTML (`<link rel="alternate"...>`).
- [ ] Fetch/parse candidate feed URLs and show picker UI when multiple feeds found.
- [ ] On subscribe, create feed for current user and backfill initial items as `is_read=true`.
- [ ] Handle invalid URLs, unreachable pages, and no-feed-found states gracefully.

### 5) RSS/Atom Fetch + Parse Pipeline
- [ ] Implement feed fetcher service using `Req`.
- [ ] Parse RSS/Atom items with robust best-effort field extraction.
- [ ] `published_at` logic: prefer item published date, fallback to updated date, fallback to fetch time.
- [ ] Normalize and sanitize item HTML before persistence.
- [ ] Cache favicon best-effort per feed with placeholder fallback.
- [ ] Dedupe items per feed/user using stable key strategy (`guid` then URL/title fallback).

### 6) Background Jobs and Scheduling
- [ ] Add Oban and configure queue(s) + cron for global feed polling every 10 minutes.
- [ ] Add manual “Refresh All” action to enqueue immediate refresh jobs.
- [ ] Add retry/backoff policy and error telemetry for failed feed fetches.
- [ ] Keep per-feed custom polling interval explicitly out of v1 scope.

### 7) Reader LiveView (3-Column + Top Navbar)
- [ ] Replace default homepage with Reader LiveView wrapped in `<Layouts.app ...>`.
- [ ] Build top navbar actions: Add Feed, Refresh All, centered search input, Mark All Read.
- [ ] Implement left column (ratio target 1): `Unread`, `All`, `Starred`, folders (expand/collapse), ungrouped feeds.
- [ ] Implement second column (ratio target 2): article rows with favicon, title, date, feed/site label, unread indicator.
- [ ] Implement third column (ratio target 4): feed name left, favicon right, title, `published_at`, content.
- [ ] Clicking feed/folder filters column 2 to read+unread items.
- [ ] Clicking article auto-marks read and loads full pane.
- [ ] “Mark All Read” affects exactly the currently displayed article scope in column 2.
- [ ] New incoming items prepend in column 2 with subtle highlight while preserving current selected article.

### 8) Feed/Folder Management
- [ ] Folder CRUD (create, rename, delete) in LiveView.
- [ ] Move feeds between folders and to ungrouped root.
- [ ] Unsubscribe feed flow with confirmation.
- [ ] Keep folder expansion state persisted per user.

### 9) Search
- [ ] Implement search across title/content/feed title/base URL.
- [ ] Prefer SQLite FTS5 virtual table/index and ranking.
- [ ] Implement fallback `LIKE` query path if FTS5 is unavailable.
- [ ] Ensure search integrates with current scope/filter and updates column 2 list.

### 10) OPML Portability (v1 included)
- [ ] Add OPML import parser to create folders + feeds for current user.
- [ ] Add OPML export generator for user subscriptions/folder structure.
- [ ] Validate malformed OPML handling and duplicate feed import behavior.

### 11) UX/Polish
- [ ] Match attached mockup structure and interaction model (layout-first parity).
- [ ] Add subtle micro-interactions: hover states, unread badge transitions, refresh/loading states.
- [ ] Ensure responsive behavior for smaller screens (progressive collapse strategy).
- [ ] Keep typography/spacing consistent and readable for long-form article content.

### 12) Testing and Acceptance
- [ ] Context tests: subscriptions, dedupe, read/star toggles, folder operations, search queries, OPML import/export.
- [ ] LiveView tests: key element IDs, add-feed modal flow, filter switching, mark-all-read behavior, article open auto-read.
- [ ] Job tests: scheduled polling enqueues, manual refresh enqueues, retry/error behavior.
- [ ] Auth/access tests: registration disabled behavior, invite/login link flow, role restrictions.
- [ ] End-to-end acceptance pass: multi-user isolation (one user’s feeds/articles/states never appear for another).

## Explicit Assumptions and Defaults
- Auth is email magic-link only for v1 (no username, no password login).
- Registration is closed by default (`REGISTRATION_ENABLED=false`).
- Data is fully isolated per user (no shared article/feed rows across users).
- Global polling interval is 10 minutes; per-feed interval is deferred.
- Initial backfill on new subscription is marked read.
- Article content source is RSS/Atom item content/summary only (no webpage readability fetch in v1).
- UI target is layout/interaction parity with provided reference, not pixel-perfect clone.
