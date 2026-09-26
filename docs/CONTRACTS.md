# Pop! contracts (frozen at G0, 2026-09-25)

The two tracks meet here: the app (Swift, `PopKit` + `App/`) and the server (Supabase Edge Functions in `supabase/functions/`). Change a contract only by editing this file first; the builder owns it. Field names are camelCase on the wire.

## 1. Domain model (PopKit)

| Type | Fields |
|---|---|
| `KidProfile` | `id` (uuid) · `firstName` · `readingLevel` (`listener` \| `early_reader` \| `reader`, PRD §8.7) · `interests` [string] |
| `StoryBrief` | `interests` [string] · `realMoment` string? · `teach` string? ("Anything you'd like this story to teach?") · `language` (default `en`) |
| `ParentSettings` | `avoidTopics` [string] · `readingLevel` override? · `language` |
| `Character` | `id` · `name` · `description` (fixed look, reused in every picture) · `referencePath` string? (Storage path of its reference image) |
| `StoryBible` | `title` string? · `setting` · `characters` [Character] · `directions` [string] (every direction so far, carried into later pages) |
| `PageContent` | `id` (uuid) · `index` · `version` (bumps on every revision) · `text` · `artPrompt` string? · `stillPath` string? · `layers` (`platePath`, `cutouts` [{`characterId`, `path`}])? · `motion` ({`scene`, `motion`})? · `clipPath` string? |
| `Book` | `id` · `kidId` · `brief` · `bible` · `pages` [PageContent] · `status` (`draft` \| `finished`) · `title` string? · `coverPath` string? · `createdAt` · `finishedAt`? |

Pictures are 16:9 until D9 is decided (important content central). Storage paths are `{userId}/{bookId}/…` in the private bucket `pop-books`.

## 2. LiveScene (app)

```swift
@MainActor protocol LiveScene: AnyObject {
    var events: AsyncStream<LiveSceneEvent> { get }   // firstFrame, clipReady(URL), failed(message), ended
    func prepare(still: Data, prompt: String) async throws   // reset → set_image → set_prompt → conditions_ready
    func start() async throws                                // start; the still shows until firstFrame
    func stop() async                                         // stop generating; the session stays warm
}
```
Implementations: `ReactorWebScene` (Orbis through `LiveSceneBridge`; records the page's clip), `StillPanScene` (slow pan fallback), `ClipReplayScene` (plays a saved clip; no network).

The web page's API (`window.popScene`, `web/live-scene/src/main.ts`) and its events (`bridge.ts` ↔ PopKit `SceneEvent`) are the bridge's own contract and change together.

## 3. Server functions

All are `POST` with a JSON body, called with the anonymous user's access token (`Authorization: Bearer …`) and the publishable key (`apikey`). Every function requires sign-in and has a per-user rate limit (ROADMAP §2 access model), except `reactor-sessions`, which is admin-only.

Every response uses one envelope, and the HTTP status matches:
```json
{ "ok": true, "data": { … } }
{ "ok": false, "error": { "code": "unauthorized | forbidden | rate_limited | bad_request | unsafe | upstream | internal", "message": "…" } }
```

### `story-turn`: one story engine turn (S1–S8, S11)
Request:
```json
{
  "mode": "turn | title",
  "bookId": "uuid",
  "kid": { "firstName": "Maya", "readingLevel": "early_reader", "interests": ["dinosaurs"] },
  "brief": { "interests": ["dinosaurs"], "realMoment": null, "teach": "sharing", "language": "en" },
  "settings": { "avoidTopics": [] },
  "bible": { "title": null, "setting": "", "characters": [], "directions": [] },
  "pages": [ { "index": 0, "text": "…" } ],
  "current": { "index": 1, "text": "draft so far, may be empty" },
  "input": { "kind": "speech | typed | continue", "speaker": "parent | kid", "text": "…" }
}
```
Response `data` for `mode: "turn"`:
```json
{
  "action": "append | new_page | revise_current | none",
  "page": { "index": 1, "text": "…", "artPrompt": "…", "breakSuggested": false },
  "bible": { "title": null, "setting": "…", "characters": [ … ], "directions": [ … ] },
  "parentNote": null,
  "timings": { "modelMs": 0, "safetyMs": 0 }
}
```
- `append`: the words continue the current page. `new_page`: the page was full, so this is the next page's draft (shown after the parent folds; the engine never turns the page). `revise_current`: a direction changed the current page. `none`: nothing for the story (for example, an unsafe request); `parentNote` explains gently.
- The server runs the kid-safety gate (PRD §8.6) before replying: `omni-moderation-latest` on the input, text and art prompt, plus an LLM rubric check at the kid's reading level. A failing page is rewritten once; if it still fails, the reply is `none` with a gentle `parentNote`. A kid's words that sound like real harm never enter the story, and only `parentNote` mentions them.
- The text obeys the reading level's limits (§8.7) and never contains surnames, addresses, schools or phone numbers.
- `mode: "title"` returns `{ "title": "Rex Learns to Share" }` from the whole book (the cover adds ", a story for {firstName}").

### `art`: one picture (S6, P2, pop-up layers, cover, kid's drawing as the hero)
Request: `{ "bookId", "kind": "page | cover | character | plate | cutout | drawing", "pageIndex": 0, "version": 1, "prompt": "…", "characters": [ Character ], "characterId": null, "drawing": null }`.
Response `data`: `{ "path": "userId/bookId/…png", "url": "signed URL, 1 h", "width": 1344, "height": 768, "placeholder": false, "ms": 0 }`.
- One locked art style for every picture. `page`, `plate`, `cutout` and `drawing` are 16:9; `cover` is 2:3; `character` is a 1:1 reference sheet on a plain background.
- Character reference images are sent to Gemini with the prompt for consistency.
- The picture passes `omni-moderation-latest`; if it's flagged it's regenerated once with a safer prompt, and otherwise `placeholder: true` comes back with no picture.
- `cutout` draws one character on flat magenta (#FF00FF), which the device removes by flood-filling the border-connected backdrop (`BackgroundKey`); `plate` is the scene without the characters.
- `drawing` turns a kid's own finger drawing into a character reference image: requires `characterId` (like `character`) plus `drawing` — a base64 PNG or JPEG, ≤ 1.5 MB decoded, rejected with `bad_request` if missing, not valid base64, oversized or neither format — and a short `prompt` describing what it is (e.g. "a purple cat with wings"). The drawing and prompt each pass `omni-moderation-latest` before Gemini ever sees them (no regeneration attempt on a flagged drawing: it comes back as `placeholder: true` immediately). Gemini is sent the drawing as an inline image and redraws it keeping the drawing's shapes, colours and features recognisable, full body and centered on the same flat magenta backdrop as `cutout`.

### `motion-prompt`: the page's animation prompt (P4)
Request: `{ "bookId", "pageIndex", "text": "…", "stillPath": "…" }` → `data`: `{ "scene": "…", "motion": "one gentle motion clause" }`. Gemini reads the page text and the still. The app builds the final prompt from the ROADMAP §2 template. Both parts pass the safety gate.

### `moderate`: ad-hoc safety check (frame tripwire)
Request: `{ "text": "…" }` or `{ "imageBase64": "…", "mimeType": "image/jpeg" }` → `data`: `{ "flagged": false, "categories": [] }`.

### `tts`: a character's line (C4, video export)
Request: `{ "text": "…", "voice": "…" }` → `data`: `{ "audioBase64": "…", "format": "mp3" }`.

### `stt-token`: speech-to-text (S1)
Request: `{}` → `data`: `{ "clientSecret": "…", "expiresAt": 0, "model": "…" }`, a short-lived OpenAI Realtime transcription secret. Audio goes from the app straight to OpenAI and is never stored.

### `reactor-token`: Orbis access (ROADMAP §2)
Request: `{ "action": "mint" }` → `data`: `{ "jwt": "…", "expiresAt": 0 }` (1 h, 2 sessions; cleans up this user's leftover sessions first). `{ "action": "report", "sessionId": "…" }` records a session the app opened. `{ "action": "cleanup" }` ends this user's recorded sessions → `data`: `{ "ended": 0 }`.

### `reactor-sessions`: admin only
Header `x-pop-admin: <REACTOR_ADMIN_SECRET>`. Request `{ "action": "list | kill" }` → `data`: `{ "open": [ { "sessionId", "state" } ] }` or `{ "ended": 0 }`. The app never calls it; the run-book does.

## 4. Database (Postgres, RLS on every table: a user sees only their own rows)

`kids`, `books` (brief, bible and settings as jsonb), `pages` (unique `book_id, index, version`), `reactor_sessions` (`session_id`, `user_id`, `opened_at`, `ended_at`), `rate_limits` (`user_id`, `fn`, `window_start`, `count`). Storage bucket `pop-books` (private; a user reads and writes only under their own `userId/` prefix).

**`reactor_sessions` and `rate_limits` are server-only (REVIEW.md R-27).** Unlike every other table, RLS grants the signed-in user's own client **no** policy at all on these two: only the service role reads or writes them (`reactor-token`'s service client, filtered by `user_id` in every query; `rate_limits` only through the `hit_rate_limit()` `security definer` RPC). This is what stops a signed-in user from resetting their own rate-limit counts or deleting their `reactor_sessions` rows through the REST API.
