# Datta Messenger — Structural Audit

**Scope:** Pre-flight read-only audit before fixes are applied. No code changes.
**Date:** 2026-05-06
**Branch:** `feature/demo-handoff-fixes`
**Requested by:** Shreyas (CTO)

This report covers five domains: (1) screen routing map, (2) WebSocket event handlers, (3) mutations without GET refresh, (4) auth/session flow, (5) S3 upload flow. Each section ends with a list of concrete issues to feed into the fix backlog.

---

## 1. Routing map of every screen

### 1.1 Routing graph

| Screen | File | Constructor params | Pushed from | Pushes to |
|---|---|---|---|---|
| LoginScreen | [login_screen.dart](../dutta_messenger_app/lib/features/auth/presentation/login_screen.dart) | none | app start; `ProfileScreen` signout | `MainShell` (success) — also has a stale push to `HomeScreen` |
| MainShell | [main_shell.dart:22](../dutta_messenger_app/lib/features/home/presentation/main_shell.dart#L22) | `user: AuthUser` | `LoginScreen` | tabbed container (no pushes) |
| DmListScreen | [dm_list_screen.dart:17](../dutta_messenger_app/lib/features/dm/presentation/dm_list_screen.dart#L17) | `me: AuthUser` | `MainShell` tab; `HomeScreen` (dead) | `ChatScreen` (per DM, line 91); `UsersScreen` (FAB, line 126) |
| GroupsScreen | [groups_screen.dart:14](../dutta_messenger_app/lib/features/groups/presentation/groups_screen.dart#L14) | `me: AuthUser` | `MainShell` tab; `HomeScreen` (dead) | `ChatScreen` for simple groups (line 89); `TopicsScreen` for topics-mode groups (line 83) |
| TopicsScreen | [topics_screen.dart:14](../dutta_messenger_app/lib/features/groups/presentation/topics_screen.dart#L14) | `group: Group, me: AuthUser` | `GroupsScreen` (line 81) | `ChatScreen` per topic with `topicId` (line 76); `GroupMembersScreen` (line 190) |
| UsersScreen | [users_screen.dart:16](../dutta_messenger_app/lib/features/users/presentation/users_screen.dart#L16) | `me: AuthUser` | `MainShell` tab; `DmListScreen` FAB; `HomeScreen` (dead) | `ChatScreen` on user tap (line 51) |
| MediaScreen | [media_screen.dart:20](../dutta_messenger_app/lib/features/media/presentation/media_screen.dart#L20) | none | `MainShell` tab; `HomeScreen` (dead) | none |
| ProfileScreen | [profile_screen.dart:24](../dutta_messenger_app/lib/features/users/presentation/profile_screen.dart#L24) | `me: AuthUser` | `MainShell` tab; `HomeScreen` (dead) | `InviteUserScreen`, `ChangePasswordScreen`, `SettingsScreen`, `AclAdminScreen` (admin-gated) |
| ChatScreen | [chat_screen.dart:26](../dutta_messenger_app/lib/features/chat/presentation/chat_screen.dart#L26) | `groupId, groupName, me, topicId?` | `GroupsScreen`, `TopicsScreen`, `DmListScreen`, `UsersScreen` | `GroupMembersScreen` (AppBar action, line 514) |
| GroupMembersScreen | [group_members_screen.dart:18](../dutta_messenger_app/lib/features/groups/presentation/group_members_screen.dart#L18) | `groupId, groupName, me` | `ChatScreen` (line 514); `TopicsScreen` (line 188) | dialogs only |
| HomeScreen | [home_screen.dart:23](../dutta_messenger_app/lib/features/home/presentation/home_screen.dart#L23) | `user` | `LoginScreen` (dead path) | duplicates all `MainShell` tab destinations |

### 1.2 Mis-scoped UI elements

- **`ChatScreen` shows the "Members" button on DMs.** [chat_screen.dart:510-514](../dutta_messenger_app/lib/features/chat/presentation/chat_screen.dart#L510) — the `IconButton` that opens `GroupMembersScreen` is rendered unconditionally. There is no gate on `chat.isGroup` / DM-vs-group distinction. Tapping it on a one-to-one DM opens the members list of the synthetic 2-person group used to back the DM. **Fix:** hide the action when the conversation is a DM (e.g. when `topicId == null` AND the conversation type is `direct`, or pass an `isGroup` flag through the constructor).

No other group-only widgets leak into DM screens, and no DM-only widgets leak into group screens.

### 1.3 Orphan / unreachable screens

- **`HomeScreen` is dead.** [home_screen.dart](../dutta_messenger_app/lib/features/home/presentation/home_screen.dart) — its action tiles duplicate the `MainShell` tabs. Login routes to `MainShell`, not `HomeScreen`. The only remaining import is the legacy push from an older login path. **Fix:** delete the file and the import.
- All other screens are reachable from at least one push site.

---

## 2. WebSocket event handlers

### 2.1 Backend (FastAPI) — `dutta-messenger-/src/modules/chat/routes/ws_routes.py`

**Inbound (client → server):**

| Type | Line | Behavior |
|---|---|---|
| `auth` | [88-103](../dutta-messenger-/src/modules/chat/routes/ws_routes.py#L88) | JWT validation; replies `connection.established` |
| `subscribe` | [114-128](../dutta-messenger-/src/modules/chat/routes/ws_routes.py#L114) | Membership check; replies `subscribed` |
| `message.send` | [130-168](../dutta-messenger-/src/modules/chat/routes/ws_routes.py#L130) | Persist + broadcast `message.new` |
| `ping` | [170-171](../dutta-messenger-/src/modules/chat/routes/ws_routes.py#L170) | Replies `pong` |
| *(unknown)* | [173-174](../dutta-messenger-/src/modules/chat/routes/ws_routes.py#L173) | `error` frame |

**Outbound (server → client):**

| Type | Trigger |
|---|---|
| `connection.established` | After auth |
| `subscribed` | After successful subscribe |
| `message.new` | Broadcast on `message.send` |
| `error` | Bad JSON, not a member, exception, unknown type |
| `pong` | Reply to ping |

### 2.2 Flutter client — `dutta_messenger_app/lib/services/chat_service.dart`

**Outbound (client → server):**

| Type | Line | Trigger |
|---|---|---|
| `auth` | [98](../dutta_messenger_app/lib/services/chat_service.dart#L98) | `connect(token)` on login |
| `subscribe` | [59,121](../dutta_messenger_app/lib/services/chat_service.dart#L59) | Manual call + auto-resubscribe on reconnect |

**Inbound handled (server → client):**

| Type | Line | State updated |
|---|---|---|
| `connection.established` | [117-122](../dutta_messenger_app/lib/services/chat_service.dart#L117) | Sets `_authed = true`; resubscribes |
| `message.new` | [124-130](../dutta_messenger_app/lib/services/chat_service.dart#L124) | Pushes onto `_streams[conversationId]` |
| `error` | [132-134](../dutta_messenger_app/lib/services/chat_service.dart#L132) | `_errorController` → SnackBar |
| *(else)* | [136-138](../dutta_messenger_app/lib/services/chat_service.dart#L136) | Silently dropped (`subscribed`, `pong`, …) |

### 2.3 Mismatches

- **Server emits, client doesn't handle:** `subscribed`, `pong` — both ack-only, low impact.
- **Client sends, server doesn't recognize:** none.
- **Schema mismatch on `message.new`:** server wraps the payload under key `"message"` and sends `sender_id` (string) + `reply_to_message_id` (string). The `WEBSOCKET.md` spec says `"payload"` with a nested `sender` object, `reply_to` object, and `media[]` array. Flutter parses the current backend shape, so the runtime is fine — but the spec and code disagree.
- **Spec features not implemented anywhere:** `message.edit`, `message.delete`, `message.pin/unpin`, `typing.start/stop`, `read.update` (and their server-side counterparts: `message.edited`, `message.deleted`, `message.pinned`, `typing.indicator`, `read.receipt`, `presence.update`). These are referenced in UI contracts and may be expected by review checklists.
- **Heartbeat:** server replies to `ping` but the client never sends one, and there is no close-on-timeout. Combined with the WS-auth gap below, sessions can quietly go dead.

---

## 3. Mutations without GET refresh

Stale-risk = response is not parsed, no follow-up GET, and there is no WS event that would reconcile state.

### 3.1 STALE-RISK call sites

| File:line | Method+endpoint | Mutates | Notes |
|---|---|---|---|
| [groups_api.dart:70](../dutta_messenger_app/lib/features/groups/data/groups_api.dart#L70) | `POST /groups/{id}/members` | Add member | Returns void; UI optimistically appends in [group_members_screen.dart:124-126](../dutta_messenger_app/lib/features/groups/presentation/group_members_screen.dart#L124). No reconciliation on success. |
| [groups_api.dart:85](../dutta_messenger_app/lib/features/groups/data/groups_api.dart#L85) | `DELETE /groups/{id}/members/{user_id}` | Remove member | Same pattern; rollback on error but no GET on success. |
| [groups_api.dart:173](../dutta_messenger_app/lib/features/groups/data/groups_api.dart#L173) | `DELETE /groups/{id}/topics/{topic_id}` | Delete topic | No response; caller [topics_screen.dart:157](../dutta_messenger_app/lib/features/groups/presentation/topics_screen.dart#L157) does optimistic remove. |
| [acl_api.dart:83](../dutta_messenger_app/lib/features/acl/data/acl_api.dart#L83) | `POST /acl/users/{user_id}/roles` | Assign role | Optimistic update + full snapshot re-fetch ([acl_admin_screen.dart:371-373](../dutta_messenger_app/lib/features/acl/presentation/acl_admin_screen.dart#L371)). Safe but inefficient. |
| [acl_api.dart:98](../dutta_messenger_app/lib/features/acl/data/acl_api.dart#L98) | `DELETE /acl/users/{user_id}/roles/{role_id}` | Revoke role | Same pattern as assign. |

### 3.2 REFRESHED (sound) — for completeness

`POST /groups`, `PATCH /groups/{id}`, `DELETE /groups/{id}` (nav pop), `POST /groups/{id}/topics`, `POST /chat/conversations/open-group`, `POST /chat/conversations/{id}/messages` (response merged + WS dedup), `PATCH /chat/messages/{id}`, `POST /chat/conversations/{id}/read`, `DELETE /chat/messages/{id}` (local deletedAt stamp), `PATCH /users/me`, `PATCH /users/me/settings`, `POST /notifications/mark-read`, `POST /notifications/tokens`, `DELETE /notifications/tokens/{id}`, `POST /media/upload/init`, `POST /media/upload/complete`, `DELETE /media/{id}`, `POST /institutions`, `POST /auth/login`, `POST /auth/invite`, `POST /auth/register`, `POST /auth/refresh`, `POST /auth/change-password`.

### 3.3 Recommendation

For group member add/remove and topic delete, either (a) return the updated entity from the backend so the client can replace local state, or (b) follow up with a GET on the listing endpoint. Optimistic-only updates are the most common cause of "I added a member and they're not in the list" bug reports.

---

## 4. Auth / session flow

### 4.1 Storage

[secure_storage.dart:9-64](../dutta_messenger_app/lib/core/storage/secure_storage.dart#L9) — `SecureTokenStorage` uses `flutter_secure_storage` (iOS Keychain / Android EncryptedSharedPreferences) with an in-memory cache. `saveTokens` writes both access + refresh atomically; `clearAll` wipes both.

### 4.2 Attach

[api_client.dart:40-56](../dutta_messenger_app/lib/core/network/api_client.dart#L40) — `_AuthInterceptor.onRequest` reads access token from secure storage and sets `Authorization: Bearer …` per request.

### 4.3 Refresh API

Backend [auth_routes.py:182-225](../dutta-messenger-/src/modules/auth/routes/auth_routes.py#L182): `POST /api/v1/auth/refresh` returns `{access_token, refresh_token, expires_in_seconds}`. TTLs ([config.py:35-36](../dutta-messenger-/src/config.py#L35)): access **30 min**, refresh **7 days**.

### 4.4 Refresh trigger

[api_client.dart:59-103](../dutta_messenger_app/lib/core/network/api_client.dart#L59) — Dio error interceptor catches 401, calls `/auth/refresh`, stores the new pair, retries the original request once. On refresh failure it calls `clearAll()`. **Limitation:** there is no global handler that pushes `LoginScreen` after `clearAll()` — the user just sees errors until they manually navigate.

### 4.5 Forced logout triggers

Only user-initiated:
- [profile_screen.dart:131-137](../dutta_messenger_app/lib/features/users/presentation/profile_screen.dart#L131): disconnect WS → revoke FCM → `authRepo.logout()` → `pushAndRemoveUntil(LoginScreen)`.
- [home_screen.dart:97-107](../dutta_messenger_app/lib/features/home/presentation/home_screen.dart#L97): same sequence (dead path).
- [auth_repository.dart:55](../dutta_messenger_app/lib/features/auth/data/auth_repository.dart#L55): `logout()` → `SecureTokenStorage.clearAll()`.

### 4.6 WebSocket auth

Client first frame is `{"type":"auth","token":"<jwt>"}` ([chat_service.dart:98](../dutta_messenger_app/lib/services/chat_service.dart#L98)). Server validates once at handshake ([ws_routes.py:82-94](../dutta-messenger-/src/modules/chat/routes/ws_routes.py#L82)) and never re-validates per frame. **There is no in-session token refresh path on the WS:** when the access token expires (30 min) mid-session, the connection stays open and the server keeps accepting frames signed with a stale identity. There is no `token.expiring` push, no proactive refresh, and no heartbeat-with-timeout.

### 4.7 Issues

- **CRITICAL — no global 401-fail-to-login.** `clearAll()` runs but the UI doesn't pivot to `LoginScreen`. Symptom: user sees API errors after refresh expires.
- **CRITICAL — WS doesn't refresh tokens mid-session.** This is almost certainly the root cause of the "tokens kept expiring" pain reported during testing. Fix options: (a) reconnect WS after every 401-driven HTTP refresh, (b) send the new token as a `auth.refresh` frame and have the server re-validate, (c) close WS at access-token expiry minus a margin and reconnect.
- **HIGH — no cross-device revocation.** Refresh token sits client-side until 7-day TTL or local logout. Admin-revoking a user on the backend doesn't push that user off other clients.
- **MEDIUM — 403 not handled.** Permission revocation mid-session surfaces as raw `FORBIDDEN` errors, no logout/redirect.

---

## 5. S3 upload flow

### 5.1 Bucket config

[config.py:51-58](../dutta-messenger-/src/config.py#L51) and [storage.py:96-102](../dutta-messenger-/src/shared/storage.py#L96):

- `STORAGE_TYPE` env var picks `"minio"` (dev, bucket `dutta-messenger`, `http://localhost:9000`) or `"s3"` (prod, bucket `dutta-messenger-prod`, `us-east-1`).
- Both buckets are private. All access is via presigned URLs.

### 5.2 Three-step upload

1. **`POST /api/v1/media/upload/init`** ([media_routes.py:43-64](../dutta-messenger-/src/modules/media/routes/media_routes.py#L43)) — body `{file_name, file_size, mime_type}`, requires `Idempotency-Key`. Returns `{upload_id, upload_url, storage_key, expires_in}`.
2. **`PUT {upload_url}` directly to S3/MinIO** ([media_uploader.dart:168-178](../dutta_messenger_app/lib/features/media/data/media_uploader.dart#L168)) — sends `Content-Type` (must match the type that was signed) and `Content-Length`.
3. **`POST /api/v1/media/upload/complete`** ([media_routes.py:72-86](../dutta-messenger-/src/modules/media/routes/media_routes.py#L72)) — body `{upload_id}`. Returns the canonical `MediaFile`, which includes `metadata.verified_size_bytes`.

### 5.3 Content-Disposition

PUT URL does **not** include `Content-Disposition` (S3 ignores it on upload anyway). It is added on the **download** side as `ResponseContentDisposition` query param when the server signs the GET ([media_service.py:326-330](../dutta-messenger-/src/modules/media/services/media_service.py#L326)): `attachment; filename="<safe filename>"`. `_safe_filename` strips quotes/newlines to block header injection. Original filename is preserved in `media_files.file_name` so downloads come back with the right name.

### 5.4 Content-Type

[media_service.py:175-180](../dutta-messenger-/src/modules/media/services/media_service.py#L175) locks the MIME type into the presigned PUT signature. The client must send the exact same `Content-Type` or S3 returns `403 SignatureDoesNotMatch`. Client picks MIME via explicit override → filename map → 64-byte sniff → `application/octet-stream`.

### 5.5 Returning URLs

`GET /api/v1/media/{id}/download` ([media_routes.py:114-126](../dutta-messenger-/src/modules/media/routes/media_routes.py#L114)) returns `{download_url, expires_in}` with a **1-hour presigned GET**. UI contract explicitly says "do not cache". Display contexts: chat bubbles, media tab, profile avatar.

### 5.6 Idempotency-Key

[idempotency.py:356-408](../dutta-messenger-/src/shared/middleware/idempotency.py#L356) — required on `init` only (not `complete`). Must be UUID4. Scoped `idempotency:{institution_id}:{user_id}:{endpoint}:{client_key}` with 24h Redis TTL. HIT → cached response, COLLISION (same key, different body) → 409.

### 5.7 1 GB limits — confirmed in four places

- [config.py:65](../dutta-messenger-/src/config.py#L65) `MAX_FILE_SIZE = 1073741824`
- [request_models.py:28](../dutta-messenger-/src/modules/media/models/request_models.py#L28) `Field(gt=0, le=1_073_741_824)`
- [media_service.py:47-50](../dutta-messenger-/src/modules/media/services/media_service.py#L47) `_IMAGE/_VIDEO/_AUDIO/_DOCUMENT_MAX_BYTES = 1024**3`
- [media_uploader.dart:14-42](../dutta_messenger_app/lib/features/media/data/media_uploader.dart#L14) `MediaLimits.hardMax = 1 GB`

### 5.8 Issues

- **HIGH — presigned GET URLs may be cached in UI state.** Each render of an old chat bubble must refetch, or the user sees `403 SignatureExpired` after an hour. There is no UI-side retry-on-expiry.
- **MEDIUM — UI contract docs mismatch code.** `docs/ui-contract/media.md` says image ≤10 MB, video ≤100 MB, audio ≤20 MB, document ≤50 MB. Code allows 1 GB for every category. Either bring docs back in line or split per-MIME caps.
- **LOW — no per-MIME granularity.** Server enforces a single 1 GB ceiling regardless of category; documented intent was per-category caps.

---

## Summary — fix backlog (in priority order)

1. **Hide group-only actions in DM `ChatScreen`** ([chat_screen.dart:510](../dutta_messenger_app/lib/features/chat/presentation/chat_screen.dart#L510)).
2. **Refresh WS auth on token rotation** — the dominant cause of mid-session pain.
3. **Global 401/403 → force logout to `LoginScreen`** in the Dio interceptor or a top-level error widget.
4. **Reconcile group member add/remove and topic delete** — return updated entity or follow-up GET.
5. **Reconcile `message.new` payload shape** with `WEBSOCKET.md` (sender object, reply_to object, media array, top-level `payload` key).
6. **Delete `home_screen.dart`** — confirmed orphan.
7. **Per-MIME size caps** — either tighten code or relax docs; pick one and enforce it.
8. **Defensive presigned-GET refetch** in chat/media bubble widgets, with a clear "URL expired, retry" UX path.
9. **Implement deferred WS events** (`message.edit/delete`, `typing.*`, `read.update`, `presence.*`) — currently unimplemented despite UI contracts.
10. **Cross-device revocation** — push session invalidation over WS or shorten refresh TTL.
