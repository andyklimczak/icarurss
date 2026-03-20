# Fever API Support Plan

## Summary
Implement Fever as a stateless controller API on top of the existing `Reader` and `Accounts` contexts, not as a parallel reader subsystem. Reuse current `Folder`, `Feed`, and `Article` data as the source of truth, add a small amount of generic sync/auth infrastructure where the current model is insufficient, and keep Fever-specific request parsing and response shaping isolated in a dedicated Fever namespace.

The first version should target the core client workflow: auth, feeds/groups relationships, item sync, unread/saved item IDs, mark operations, and client-friendly endpoint compatibility. XML, Hot Links, Sparks, and Kindlings should not drive the design; return empty Fever-compatible payloads for optional unsupported features instead of inventing new core concepts.

## Implementation Changes
### 1. Shared external-reader auth in `Accounts`
Add a generic per-user external-reader access record under `Accounts`, because the secret is shared across Fever now and Google Reader later.

Suggested structure:
- `lib/icarurss/accounts/reader_api_access.ex`
- Keep public lifecycle/auth functions on `Icarurss.Accounts`

Schema shape:
- `user_id` unique
- `enabled` boolean
- `api_password_hash` for future raw-password protocols like Google Reader
- `fever_api_key_hash` for direct Fever lookup
- `last_rotated_at`

Behavior:
- Per-user opt-in only
- Generated secret only; show it when enabled/reset, never persist plaintext
- Fever auth verifies by hashing the incoming `api_key` and looking up the enabled access row directly
- Username is the documented identifier clients should use when generating the Fever key
- If username changes, force-reset/disable shared external-reader access, because Fever sends only the derived key and it cannot be recomputed safely from stored hashes

Public `Accounts` API to plan for:
- `get_or_create_reader_api_access/1`
- `enable_reader_api_access/1` returning `{access, plaintext_secret}`
- `reset_reader_api_access/1` returning `{access, plaintext_secret}`
- `disable_reader_api_access/1`
- `authenticate_fever_api_key/1`
- `authenticate_reader_api_credentials/2` for later Google Reader reuse

### 2. Generic sync/query additions in `Reader`
Keep “get data / mutate data” in core, since that logic is protocol-agnostic.

Add generic reader-facing sync functions for:
- listing groups from folders
- listing feeds plus folder/group relationships
- listing sync items ordered by `article.id desc` with Fever-style filters:
  - `since_id`
  - `max_id`
  - `with_ids`
  - `feed_ids`
  - `group_ids`
  - `limit`
- listing unread item IDs
- listing saved item IDs
- marking one item read/unread
- marking one item saved/unsaved
- marking feed items read, optionally bounded by `before`
- marking group items read, optionally bounded by `before`
- computing a sync timestamp for `last_refreshed_on_time`

Use existing models as the mapping:
- `Folder` -> Fever group
- `Feed` -> Fever feed
- `Article` -> Fever item
- `Article.is_starred` -> Fever saved item
- unread derived from `Article.is_read == false`

Do not reuse the current UI article query for Fever items; Fever should use dedicated ID-based sync queries rather than `published_at` sorting.

### 3. Generic favicon cache in core
Because Fever favicon payloads are not just URLs, add a reusable favicon cache to the reader domain instead of making this a Fever-only hack.

Suggested structure:
- `lib/icarurss/reader/favicon.ex`
- core functions on `Icarurss.Reader`

Data shape:
- one cached favicon record per feed or per favicon URL
- binary/icon payload plus mime type or normalized encoded form
- timestamps for refresh/caching

Behavior:
- populate/refresh favicon cache when feeds are subscribed/refreshed
- keep existing `favicon_url` on feeds for web UI compatibility
- expose a generic reader function that returns Fever-ready favicon source data for feeds

This keeps favicon fetching reusable for both the web app and external APIs.

### 4. Fever protocol namespace and web layer
Keep Fever-specific command dispatch and serialization out of `Reader`.

Suggested structure:
- `lib/icarurss/integrations/fever.ex`
- `lib/icarurss/integrations/fever/request.ex`
- `lib/icarurss/integrations/fever/serializer.ex`
- `lib/icarurss_web/controllers/fever_controller.ex`
- `lib/icarurss_web/plugs/fetch_reader_api_scope.ex`

Responsibilities:
- controller stays thin and accepts POSTed Fever params
- auth plug validates Fever `api_key`, then assigns `current_scope` so controller code stays consistent with the rest of the app
- Fever module dispatches supported commands and builds protocol-shaped payloads from generic `Reader` results

Supported Fever surface for v1:
- auth handshake
- `groups`
- `feeds`
- `feeds_groups`
- `items`
- `unread_item_ids`
- `saved_item_ids`
- `favicons`
- `mark`

Optional unsupported requests:
- `links`
- `sparks`
- `kindlings`

For those, return empty Fever-compatible payloads rather than errors.

Response policy:
- JSON only in v1
- ignore `xml=1` rather than adding XML generation
- always include Fever-required top-level metadata such as auth status and refresh timestamp

### 5. Router and settings surface
Router placement:
- Add controller routes in a new controller scope using `pipe_through [:api, :reader_api]`
- Expose both `POST /api/fever` and `POST /fever`
- Use controller routes, not LiveView routes and not the browser pipeline, because Fever is a stateless third-party API and must not depend on browser session auth or CSRF
- Do not place Fever under an existing `live_session`; it is not a LiveView feature

Settings placement:
- Add a new `:api` action to the existing authenticated settings LiveView inside the current `live_session :require_authenticated_user` block
- Add `live "/users/settings/api", UserLive.Settings, :api` there because this page requires a logged-in user and must keep `current_scope`
- The new API tab should allow:
  - enable access
  - show username + endpoint URLs
  - reveal generated secret once after enable/reset
  - reset secret
  - disable access
  - explain that the same secret is intended for Fever now and Google Reader later

## Test Plan
### Accounts / auth
- enabling API access creates exactly one access record per user
- reset rotates both password and Fever verifier
- disable prevents Fever auth
- Fever auth resolves the correct user from `api_key`
- username change disables/resets external-reader access

### Reader sync
- group/feed/item list functions stay user-scoped
- item filters work for `since_id`, `max_id`, `with_ids`, `feed_ids`, and `group_ids`
- unread/saved ID lists match article state
- item/feed/group mark operations update only the intended records
- favicon cache functions return data in a reusable form

### Controller / protocol
- `POST /api/fever` and `POST /fever` both authenticate and return Fever-compatible payloads
- unauthenticated requests return `auth: 0`
- supported commands return the right top-level sections
- optional unsupported commands return empty payloads rather than `500`s
- mark commands mutate read/saved state correctly
- JSON-only behavior is stable when `xml=1` is present

### Settings UI
- authenticated users can open the new API tab
- enabling/resetting shows the generated secret
- disabling removes active access
- API tab uses the existing authenticated settings route scope correctly

## Assumptions and Defaults
- Shared external-reader auth is generic and lives in `Accounts`; Fever-specific shaping lives outside `Reader`
- Username is the canonical identifier users enter into compatible clients
- Changing username forces external-reader auth reset
- Fever v1 is JSON-only
- Hot Links, Sparks, and Kindlings are not modeled in core; return empty Fever-compatible payloads
- Fever item sync uses article IDs and dedicated sync queries, not the web reader’s published-date ordering
- Favicons are worth modeling generically in core because the current `favicon_url` field is not sufficient for Fever payloads
