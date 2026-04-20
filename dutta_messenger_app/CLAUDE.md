# CLAUDE.md — DuttaMessenger Flutter app

## Mandatory pre-flight for any groups or media work

> Read `docs/ui-contract/groups.md` and `docs/ui-contract/media.md` start
> to finish before writing any code. The minimum-implementation checklist
> at the bottom of each doc is the scope — stick to it. If you hit a
> pitfall, check the pitfalls table before guessing.

Both docs live in the **backend repo**, not this one. In this monorepo
layout they resolve to:

- `../dutta-messenger-/docs/ui-contract/groups.md`
- `../dutta-messenger-/docs/ui-contract/media.md`

(Also accessible on GitHub at
`https://github.com/shreyasananth-3/dutta-messenger-/tree/main/docs/ui-contract/`.)

### What "read start to finish" means here

You must use the Read tool on each file — skimming, `grep`, or relying on
what you remember from a previous session is not acceptable. The docs
contain exact field names, status codes, idempotency rules, and pitfalls
that are easy to guess wrong.

### The minimum-implementation checklists are the scope

Each doc ends with a checklist titled "Minimum \<feature\> implementation"
(groups.md §"Minimum 'groups tab' implementation"; media.md §"Minimum
'attach file to message' implementation"). **Do exactly those items.**
Do not add features not on the list — no read receipts, no typing
indicators, no group avatar upload UI until that's explicitly requested
and added to the checklist.

### Pitfalls tables come before guessing

media.md ends with a "Common pitfalls" table (§"Common pitfalls"). If you
see `403 SignatureDoesNotMatch`, `403 PERMISSION_DENIED` on complete, or
cached `download_url` returning 403 later — consult that table before
changing code. Same policy applies as new pitfall tables land.

---

## House rules that also apply (short list)

- Chat delivery is WebSocket-primary, never polling — see
  `../dutta-messenger-/docs/ui-contract/websocket-integration.md` and the
  live `ChatService` singleton at `lib/services/chat_service.dart`.
- `API_BASE` is read from `.env` at app start (via `flutter_dotenv`).
  Do not hardcode URLs in Dart.
- Every API call goes through `ApiClient().dio` (see
  `lib/core/network/api_client.dart`) which already attaches the Bearer
  token, ngrok skip-warning header, and request id.
- Tokens live in `SecureTokenStorage` (`lib/core/storage/secure_storage.dart`).
  Never put them in `SharedPreferences`.
- The groups feature uses the `GroupsApi` at
  `lib/features/groups/data/groups_api.dart` — extend that, don't create
  a parallel client.
- Feature-first directory layout under `lib/features/<feature>/{data,domain,presentation}/`.
  Keep new groups/media code under `lib/features/groups/` and
  `lib/features/media/` respectively.
