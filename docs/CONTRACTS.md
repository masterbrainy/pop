# Pop! contracts (frozen at G0, 2026-09-26)

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

### `story-turn`: title, and the story path (P-04; S1–S8, S11, S12, S14)
`mode: "turn"` (the pre-P-04 append/new_page/revise_current engine) was removed once the app moved to `path`/`page` and the full eval passed on them.

Request: `mode`, the bible (which now carries the path) and the pages **already shown** (`pages`, oldest first).
```json
{
  "mode": "path | page | title",
  "bookId": "uuid", "kid": { … }, "brief": { … }, "settings": { … },
  "bible": { "title": null, "setting": "…", "characters": [ … ], "directions": [ … ],
             "path": [ "Maya finds a red kite in the meadow.", "…", "Maya falls asleep holding the kite. The end." ] },
  "pages": [ { "index": 0, "text": "…" } ],
  "index": 1,
  "input": { "kind": "speech | typed", "speaker": "parent | kid", "text": "wake the dragon up" }
}
```
- `mode: "path"` plans the story path, or re-plans it, from `index` onward, then writes page `index`.
  - At the start: `index: 0`, no `input`; the brief drives the path.
  - For a direction: `index` is the page behind the one on screen, and `input` carries the direction.
  - Beats before `index` (pages already shown) are never changed. The new path has about 5–8 beats in total, and its last beat always ends the story.
  - When a direction explicitly asks to end the story now (for example "the end", "let's finish the story here with a proper ending"), the re-planned path always ends at the page being written (`index`) instead, overriding the usual 5–8 beat guidance.
- `mode: "page"` writes page `index` from the existing `bible.path[index]`, with no re-planning and no `input`. The app calls it after each fold, for the new page behind.
- `mode: "title"` returns `{ "title": "Rex Learns to Share" }` from the whole book (the cover adds ", a story for {firstName}"); it needs only `bookId`, `kid`, `bible` and `pages`.

Response `data` for `path`/`page`:
```json
{
  "action": "page | none",
  "page": { "index": 1, "text": "…", "artPrompt": "…", "question": "…", "isEnding": false },
  "bible": { "title": "…", "setting": "…", "characters": [ … ], "directions": [ … ], "path": [ "…" ] },
  "parentNote": null,
  "refusal": "real_harm | unsafe | null",
  "timings": { "modelMs": 0, "safetyMs": 0 }
}
```
- `page.isEnding` is true for the path's last beat; after it there's no page behind, and the parent closes the book to finish.
- **Input safety (R-37, PRD §8.6):** `input.text` is moderated before it reaches the model. If it's flagged, or it sounds like the child describing real harm, the reply is `action: "none"` with the unchanged bible and a calm `parentNote`, and the words never enter the story.
- The page goes through the output gate: moderation plus the rubric at the reading level, with one rewrite, then `none`. Its text is kept within the level's word limit (cut to whole sentences, never refused for length), it never retells earlier pages, and for an "en" brief it never mixes in a letter from another script (any other language passes through unchecked).
- `page.question` is one short question for the parent to ask about the page (C3).
- `refusal` (R-41) is set only on `action: "none"` and only for a safety refusal, never for reaching the path's end: `"real_harm"` when a kid's own words sounded like real harm (input moderation or the real-harm rubric, R-37), `"unsafe"` when an input or the output failed moderation, the rubric or the language check for any other reason, and `null` otherwise (a safe page, or `page` mode past the path's end). `parentNote` stays the calm, non-alarming text either way; `refusal` is for the app to tell the two cases apart without parsing the note.

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
Request: `{ "action": "mint" }` → `data`: `{ "jwt": "…", "expiresAt": 0 }` (`expiresAt` in Unix seconds; the app also reads a value above 1e12 as milliseconds, which older deployments sent) (1 h, 2 sessions; cleans up this user's leftover sessions first). `{ "action": "report", "sessionId": "…" }` records a session the app opened. `{ "action": "cleanup" }` ends this user's recorded sessions → `data`: `{ "ended": 0 }`.

### `reactor-sessions`: admin only
Header `x-pop-admin: <REACTOR_ADMIN_SECRET>`. Request `{ "action": "list | kill" }` → `data`: `{ "open": [ { "sessionId", "state" } ] }` or `{ "ended": 0 }`. The app never calls it; the run-book does.

## 4. Database (Postgres, RLS on every table: a user sees only their own rows)

`kids`, `books` (brief, bible and settings as jsonb), `pages` (unique `book_id, index, version`), `reactor_sessions` (`session_id`, `user_id`, `opened_at`, `ended_at`), `rate_limits` (`user_id`, `fn`, `window_start`, `count`). Storage bucket `pop-books` (private; a user reads and writes only under their own `userId/` prefix).

**`reactor_sessions` and `rate_limits` are server-only (REVIEW.md R-27).** Unlike every other table, RLS grants the signed-in user's own client **no** policy at all on these two: only the service role reads or writes them (`reactor-token`'s service client, filtered by `user_id` in every query; `rate_limits` only through the `hit_rate_limit()` `security definer` RPC). This is what stops a signed-in user from resetting their own rate-limit counts or deleting their `reactor_sessions` rows through the REST API.
