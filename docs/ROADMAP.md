# Pop! — Execution Roadmap

*Status: DRAFT v3.1 · 2026-09-26 · P-01 (parents drive creation; saved books replay exactly; lessons optional) · P-02 superseded (everything is free) · P-03 (iPhone Duo only) · P-04 (story path; page built behind the current one) · v3.1 adds the readiness fixes from REVIEW.md · Implements: [PRD.md](PRD.md)*

**Planning assumptions.** Two engineers (Brian plus a teammate) building with Claude Code. Estimates are in **focused hours** and include tests. **There's no deadline (D8, resolved), so we build the full scope in phase order.** The cut lines in §7 are kept only as a fallback. Everything is built and demoed **only on the iPhone Duo simulator in Xcode 27.1 beta**.

---

## 1. Where we are (Day 0, done 2026-09-26)

| Item | Status |
|---|---|
| Xcode 27.1 beta (27A9269) installed and selected; license accepted; first-launch components installed | ✅ |
| Old Xcode 27.0 and every iOS 27.0 simulator image removed | ✅ |
| iOS 27.1 simulator; the **iPhone Duo** boots to its home screen with DeviceHub.app open (REVIEW R-21) | ✅ |
| Duo APIs checked in the SDK (see §3) | ✅ |
| Supabase CLI logged in and linked to the project | ✅ |
| API keys (Reactor, OpenAI): each returns HTTP 200, stored in Supabase secrets and the git-ignored `supabase/functions/.env` | ✅ |
| App-side Supabase URL and publishable key in git-ignored `config/Supabase.local.xcconfig` | ✅ |
| Private GitHub repo `masterbrainy/pop` | ✅ |
| Claude Code ↔ Xcode tools (`xcrun mcpbridge`) | ✅ |
| Claude Code ↔ iOS Simulator panel attached to the **iPhone Duo**. The 466×678 pt seen at first boot is the Duo's **outer** screen (it booted closed); the inner screen is 951×669 pt | ✅ |
| Sibling sessions running: Review & QA and Pivots & Ideas (roles in `CLAUDE.md`) | ✅ |
| **Build gate:** Brian verifies the setup and says to start | ⏳ |

## 2. Architecture at a glance

```
┌──────────────────────────── iOS app (SwiftUI, iOS 27.1) ────────────────────────────┐
│  Posture          Book UI                    Story pipeline (actor)    Living page  │
│  HingeSource ──▶  SpreadView (Arrangement)   SpeechInput ─▶ StoryEngine LiveScene    │
│  PostureMachine   TextPage | ArtPage ◀────── PagePipeline ─▶ Art     ◀─ (WKWebView + │
│  (pure, tested)   PageCurl · PopUp · Cover   StoryBible · Moderation    Reactor JS)  │
│                   Bookshelf                  Narration                 StillPan fb   │
└───────────────┬────────────────────────────────────┬────────────────────┬───────────┘
                │ Supabase (auth, Postgres, Storage)  │ Edge Functions     │ WebRTC
                ▼                                     ▼ (keys live here)   ▼
          books/pages/characters/bible        stt-token · story-turn   Reactor Orbis
          images · layers · clips             art · motion-prompt      (video per page)
                                              moderate · tts
                                              reactor-token · reactor-sessions
```

**Units and their contracts.** Each unit is testable on its own.

| Unit | Responsibility | Depends on |
|---|---|---|
| `HingeSource` | Emits posture updates `(status, angle)`. Two versions: Duo (`onHingeChange`) and a debug slider. iPhone Duo only (P-03). A nil hinge means "unknown" (it can be brief on a Duo, when the view leaves a hierarchy that gets hinge updates), so the last posture is kept | — |
| `PostureMachine` | Pure function from a stream of angles to effects: curl progress, turn committed or cancelled (with hysteresis), pop depth for the page now showing, and closed (after a ~1 s hold). Angles are normalised to the range measured in 0.1 | `HingeSource` values |
| `PagePipeline` | Keeps the page behind the current one fully built: text → art → layers → animation prompt. A direction cancels and rebuilds the page behind; the page on screen never changes | StoryEngine, Art, Moderation |
| `StoryEngine` | Plans a **story path** from the brief (interests, optional real moment, optional "teach something" note): an ordered list of page beats that always reaches an ending. It writes pages one at a time along the path. A direction (spoken or typed, parent or kid) re-plans the path from the page behind onward and rewrites that page. Output: path, page text, art prompt, bible and direction updates, parent question | `story-turn` function |
| `Art` | OpenAI `gpt-image-2.5-flare` page illustration at 1536×1024, cropped to 16:9 in the app (P-05; framing for the portrait page set at G0; see §3), background plate, character cutouts, cover | `art` function |
| `MotionPromptBuilder` | Builds the Orbis prompt for **one page only** from a fixed template (below) | `motion-prompt` function |
| `LiveScene` | Protocol: `prepare(image:prompt:)`, `start()`, `stop()`, event stream. Implementations: `ReactorWebScene` (also records each page's clip), `StillPanScene` (fallback) and `ClipReplayScene` (plays a saved page's recorded clip) | Reactor JS SDK |
| `SessionController` | Orbis session lifecycle: warm-up, token, reconnect with backoff, kill, server-side cleanup of stray sessions, credit meter | `reactor-*` functions |
| `BookStore` | Saves a finished book (rows, pictures, layers, clips) and keeps a copy on the device, so a saved book shows exactly and works offline | Supabase |

**Per-page animation sequence (PRD P3–P5).** On page shown (fully open):
`reset → set_image(page still) → set_prompt(page motion prompt) → wait for conditions_ready → start`. The still stays on screen until the first frames arrive, because the first chunk after start contains none. A drift guard re-anchors, or pauses and holds the frame, after *T* seconds, where *T* comes from the Phase 0 spike. On flip, the same sequence runs for the next page. Orbis audio is off during creation. While the final version of a page plays, its clip is recorded (length and looping set at G0) and saved with the page. A page turned before its clip is complete is re-animated and recorded before the book is saved. When a saved book is shown, `ClipReplayScene` plays that clip instead and no Reactor session is needed.

**Motion prompt template.** This applies the teammate's continuity lesson. `SCENE` (from this page's text plus its illustration) and `CAMERA` stay identical within the page, and only one gentle motion clause varies:
`"The same {SCENE}, the same {CAMERA: locked-off, still}. {ONE GENTLE MOTION CLAUSE}. Nothing new enters the scene. Continuous slow motion, no cuts."`

**Server access model (built in 0.6).** Anyone who reaches the functions' address must not be able to spend the demo's Reactor credit or kill its session.
- The app signs in anonymously with Supabase Auth. Every server function requires that sign-in and has a per-user rate limit.
- `reactor-token` mints Reactor tokens that last 1 h and allow 2 sessions (one live plus one reconnect); the app asks for a fresh one when a token expires or runs out. The app reports each Orbis session it opens, and the same function cleans up that user's own leftover sessions (at launch, and before minting).
- `reactor-sessions` (list, and kill every session on the account) is admin-only: it needs a server-side admin secret and the app never calls it. The run-book uses it after a demo. The Reactor account is Brian's own (REVIEW R-23), so killing everything on it is safe.
- API keys never leave the server. 0.3b checks whether a running session survives its token expiring; if it doesn't, G0 sets the token lifetime and the run-book's warm-up time together.

## 3. Platform facts

### iPhone Duo APIs, verified in the iOS 27.1 SDK

These were checked by reading the SDK's `SwiftUICore` interface file on 2026-09-26.

| API | Signature | Use in Pop! |
|---|---|---|
| Hinge | `func onHingeChange(isEnabled: Bool = true, _ action: @escaping (_ oldContext: DeviceHingeContext, _ newContext: DeviceHingeContext) -> Void) -> some View` · `DeviceHingeContext.hinge: DeviceHinge?` (nil when there's no hinge, and also when the view leaves a hierarchy that gets hinge updates, so nil can be brief on a Duo: `UIHingeInteraction.h`) · `DeviceHinge.status`: a **struct with static members** `.closed / .partiallyOpen / .fullyOpen`, **not an enum**, so compare with `==`, and any `switch` needs a `default`. `.fullyOpen` means "open as far as the device allows", so the flat angle isn't documented · `DeviceHinge.angle: Angle` (UIKit's `UIHinge.angle` is a `CGFloat` in **radians**) · **The rate and granularity of angle updates are "system policy"** (`UIHinge.h`), so don't rely on update frequency or precision · UIKit's handler is called with the initial state; 0.1 checks whether `onHingeChange` is too | `status` → mode (book or cover); `angle` → curl progress and pop depth, **animated smoothly between samples** |
| Two-pane layout | `ArrangementView { primary } secondary: { secondary }`: both are `@ContentBuilder` closures, and there are only ever two panes · `.arrangementViewStyle(.split / .overlay)` · `.splitArrangementLayoutRatio(_:)` | The spread: primary = text page, secondary = art page |
| Reserved regions | `GeometryProxy.reservedRegions(kind: .occlusion / .division, options: [.includeInactive], layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]`, each with `frame`, `margins`, `isActive` | Pad text and position the art away from the fold (`.division`) and camera (`.occlusion`). UIKit's docs (`UIViewReservedRegion.h`): `.occlusion` is "a region that is occluded by an element" (the camera) and `.division` is "a region where an element should divide into two separate regions" (the fold); `frame` includes margins for interactive content |
| UIKit versions | `UIHingeInteraction`, `UIArrangementViewController` | Not needed (the app is SwiftUI) |
| Cover display | **No dedicated API in the SDK.** The simulator's Duo has two screens (its `capabilities.plist`): outer 466×678 pt, and inner 951×669 pt folding down the middle, so each page is about 475×669 pt, portrait | `.closed` → cover view on the outer screen. 0.1 confirms the app's scene moves there when closed |

### Reactor Orbis, from Reactor's docs and the teammate's starter

- There is **no Swift SDK**. Stable documents JavaScript (`@reactor-team/js-sdk` 3.x) and Python; Dynamic also lists raw WebRTC. So we host the JS SDK inside a `WKWebView`, bundled into the app rather than loaded from the web.
- `set_image` works only before `start`; changing it needs `reset` + `start`. `set_prompt` works mid-run and takes effect at the next ~1.8 s chunk. The first chunk after `start` has no frames.
- Session startup takes **minutes**. Tokens come from `POST https://api.reactor.inc/tokens` (up to 6 h, capped by a maximum session count); Pop! mints 1 h tokens for 2 sessions (§2 access model). A failed connect can leave a session running that only the API key can delete.
- **Stable:** 832×480 at 18 fps native, delivered at up to 4K, $0.582/min. **Dynamic:** 640×368, $1.254/min, can change resolution live, sessions up to ~60 min. Still **unknown** (0.3b asks, and we ask Reactor): whether billing counts from connection or from generation, how long a Stable session can live, and what idle time between pages costs. If billing starts at connect, an hour of warm-up alone costs about $35.
- Input images work best at 16:9; other shapes get squashed. **Each Duo page is portrait (about 475×669 pt, aspect 0.71), so cropping a 16:9 frame to one page keeps only about 40% of its width**: about 332 of Stable's 832 native pixels, stretched about 4× across the page. 0.3b compares four ways to fill the page, and G0 decides (D9):
  - (a) span the animation across the whole spread (keeps about 80%), with the text on a calm band. This changes the page layout, so it goes to Brian as a pivot if chosen;
  - (b) compose the picture in portrait at the centre of the 16:9 frame and crop to it (the current plan);
  - (c) Dynamic's live resolution change, if it allows a portrait shape;
  - (d) stretch the portrait picture sideways to 16:9, send that, and squeeze the video back to the page's shape, which keeps all 832 pixels across (check that motion still looks natural).

### Other facts that affect the design

- **Xcode 27.1 has no Simulator.app.** `DeviceHub.app` (in `Xcode-beta.app/Contents/Applications`, bundle `com.apple.dt.Devices`) shows the simulators. Xcode's foldable-device plugin (`CoreDevicePopDeviceKitExtension`) adds a hinge slider to the Duo's window there. By default it sweeps through the fold instead of jumping, and a "Disable Hinge Interpolation" setting sends a single angle instead. (Found in the plugin's code; 0.1 confirms it on screen.) A Duo booted without DeviceHub open stays on the Apple logo (REVIEW R-21).
- Gemini's image models (2.5 Flash Image, 3.1 Flash Image, 3 Pro Image) have **no free tier**. On the paid tier they cost about $0.04–0.13 per image, and prompts aren't used to improve Google's products (Google's pricing and billing pages, checked 2026-09-26). With no shape requested, `gemini-2.5-flash-image` returns a square 1024×1024 PNG (test picture, 2026-09-26), so 0.4 asks for the page's shape.
- Apple's Vision background removal (`VNGenerateForegroundInstanceMaskRequest`) reportedly **doesn't run in the Simulator** (Apple Developer Forums). So pop-up layers are generated directly: a background plate plus character cutouts on a flat colour that Core Image keys out.
- OpenAI text-to-speech **returns no word timings**, so read-along uses `AVSpeechSynthesizer`'s `willSpeakRangeOfSpeechString` callback. OpenAI's `tts` is used only for talking characters and video export.
- OpenAI Realtime supports transcription-only sessions, with **short-lived client secrets minted by our server**, so the app never holds the key.

### Phase 0 probe results (Duo simulator, iOS 27.1, 2026-09-26)

- **0.1 Hinge.** `onHingeChange` fires once on appear with the current state (closed, 0.00°, about 0.5 s after launch), so the app needs no separate first read. When the Duo is closed, the app runs on the outer screen (466×678 pt) and the inner screen stays black. `devicectl device motion hinge-angle` reports 0–180°. Only DeviceHub's slider moves the hinge: `simctl` and `devicectl` can't set it, and computer control is off on this Mac. So posture logic is built and tested against a scripted `HingeSource` and the in-app debug slider, and the real hinge is a manual check for Brian.
- **0.2 Spread (outer screen).** On the closed Duo's portrait outer screen, `ArrangementView(.split)` stacks the two panes top and bottom, 466×339 pt each. There is no `.division` region there, and there are two active `.occlusion` regions at the top right: the camera [399,29 37×37] and its housing [382,0 84×170]. The inner spread (expected 2 × about 475×669 pt) is measured when the hinge is opened by hand.
- **Logs.** `simctl spawn … log` fails on this Mac (`getpwuid_r`), so probes also write `Documents/<probe>.log`, which the Mac reads through `simctl get_app_container`.
- **0.3a Orbis go/no-go: GO (2026-09-26).** Reactor's JS SDK in the app's WKWebView streams Orbis video on the Duo simulator: connect 3.5 s, prepare (upload → `set_image` → `set_prompt` → `conditions_ready`) 1.6 s, `start` → `generation_started` 58 ms, **first frame 4.8 s after start**, 33 frames per ~2 s chunk, 17–18 fps at 7–10 Mbit/s, delivered at 2560×1440 ("2k"; input still 1344×768). Session start-up is seconds, not minutes, so warm-up can be short. `disconnect()` ended the session (0 open afterwards). **Style drift:** from a watercolor still, Orbis rendered a photoreal fox within seconds, so the scene part of the motion prompt restates the art style. Log: `build/probe/orbis-run-3.txt`.
- **Real hinge in DeviceHub (2026-09-26): works when the Mac isn't overloaded.** The hinge slider is hidden behind an internal flag (`defaults write -g com.apple.dt.coredevicepop.useInternalV68ActionBar -bool YES`, then restart DeviceHub; restarting DeviceHub shuts the Duo down). At load averages of 60–400 the simulated Duo never reached the commanded angle ("Falling back"); at load ≈ 5 it follows the slider (`devicectl device motion hinge-angle` 0 → 180°), the app moves to the inner screen and shows the two-page spread (text left, picture right, 2853×2007 px). Opening can leave the inner display asleep and black in DeviceHub until the screen is clicked once. **The app's hinge updates are sparse:** `onHingeChange` and `UIHingeInteraction` report identical values, roughly one per status change or pause (a fold to 103° may arrive only as 154°), so a quick fold can be missed; a slow fold with a pause turned the page (180 → 103 → 180: `turnCommitted`, then `popBegan`). The in-app hinge panel stays as the reliable demo control.
- **0.4 (first result).** `generationConfig.imageConfig.aspectRatio: "16:9"` works on `gemini-2.5-flash-image`: a 1344×768 PNG in 5 s.

## 4. Reusing the teammate's starter (with permission)

| Source in `orbis-hackathon-starter` | Becomes in Pop! |
|---|---|
| `app/api/token/route.ts` | `supabase/functions/reactor-token`: ported to Deno, plus sign-in, a rate limit, and 1 h tokens for 2 sessions (§2 access model) |
| `app/api/sessions/route.ts` | `supabase/functions/reactor-sessions` (list and clean up sessions), **admin-only**. The starter's unauthenticated "kill every session" isn't ported as-is |
| `hooks/use-orbis-session.ts` | `web/live-scene/` bridge: connect and reconnect with backoff, wait for `conditions_ready`, a single prompt path with a chunk-stamped log, event handling, kill and cleanup |
| `lib/orbis.ts` | Message unwrapping, fallback for the chunk-index field name, credit constants |
| `lib/scene.ts` | The pattern behind `MotionPromptBuilder` (fixed scene and camera, one changing clause) |
| `components/status-panel.tsx` | Pattern for the in-app debug overlay: status, chunk, prompt log, errors, credit meter, KILL |
| README flow (image model → image-grounded prompt → Orbis start image) | The per-page pipeline, with Gemini doing both steps |

## 5. Phases

Tracks: **A** = device and UI · **B** = AI and backend. The two tracks meet at the `PageContent` model and the `LiveScene` protocol, which are defined in Phase 0 so both can work against mocks.

### Phase 0: Probes and foundations (≈ 18 h · A 11, B 7)

| Task | Track | Est | Answers |
|---|---|---|---|
| 0.1 Hinge probe screen: show `status` and `angle` live while moving DeviceHub's hinge slider (`simctl` has no hinge command; see §3) | A | 2 h | Is the angle continuous, and how often does it update? What is the angle when closed and when fully open (the maximum isn't documented)? Does `onHingeChange` fire with the initial state? Does the app's scene move to the outer screen on `.closed`? |
| 0.2 Spread probe: `ArrangementView` split, and the reserved regions drawn as overlays | A | 1 h | The real page size (expected about 475×669 pt, portrait), and where the fold and camera are |
| 0.3a Orbis go/no-go: `WKWebView` + bundled JS SDK + a short-lived token minted on the Mac (the key never enters the app) → one picture animating in the Duo simulator | A | 3 h | Does WebRTC video play in a `WKWebView` in the simulator? **If not (plan B):** try a native WebRTC client. Only Dynamic documents raw WebRTC, so this means Dynamic's price (about 2× Stable) and 640×368 video. If that fails too, pages fall back to the still with a slow pan, which drops a must-have, so it goes to Brian as a pivot |
| 0.3b Orbis comparisons and clip recording | A | 5 h | Warm-up time; time from `reset` to first frame; drift after 30 and 60 s; Stable vs Dynamic on 3 picture-book images; the four page-shape options (§3). **Clips:** `MediaRecorder` on the received stream, bytes moved to native in chunks or through a `WKURLSchemeHandler`, recorded at native resolution, MB per clip; whether ReplayKit works in the simulator as the native fallback (`WKWebView.takeSnapshot` is too slow for video). **Billing:** does it start at connect or at generation, how long can a Stable session live, what does idle time cost (also ask Reactor), and does a running session survive its token expiring? |
| 0.4 Gemini probe: page art with a character reference at 16:9, plus plate and cutout edits. Needs Gemini billing on (§1) | B | 2 h | p50 latency, character consistency, how well the cutouts key out |
| 0.5 Speech probe: Mac mic → simulator → OpenAI Realtime transcription using a short-lived secret | B | 2 h | End-of-speech detection, latency, whether Apple on-device speech works in the simulator |
| 0.6 Backend skeleton: schema, the access model in §2 (anonymous sign-in, sign-in required on every function, rate limits, admin-only session cleanup), `reactor-token`, `reactor-sessions`, stub functions, secrets. Needs Deno and a running Docker (REVIEW R-07) | B | 3 h | — |

**Gate G0:** confirm D1 (the gesture model in PRD §13) and set its numbers from 0.1: turn angle, hysteresis, pop angle and the close hold. Decide D3 (Stable or Dynamic) and D9 (how the animation fills a portrait page). Settle D4's details: how clips are recorded, the minimum clip length, how clips loop (crossfade or ping-pong), and what Save does with pages that have no complete clip. Set the token lifetime and the run-book's warm-up time from 0.3b. Fix the latency budget, and freeze the `PageContent` and `LiveScene` contracts.

### Phase 1: Book shell and hinge (≈ 8 h · A) · must-have: curl

- App skeleton and navigation: Bookshelf → New Book → Book.
- Domain models (`Book`, `Page`, `Character`, `StoryBible`, `KidProfile`, `StoryBrief`) and mock data.
- `HingeSource` (Duo and debug slider) and **`PostureMachine` built test-first**, driven by scripted angle sequences. These include **sparse, irregular and jumpy updates** (the update rate is system policy), and the curl smooths between samples. They also cover reopening before the turn point, jitter around it, a brief overshoot to `.closed`, and opening from the cover.
- `SpreadView`: left text page, right art page (still only for now), padded for reserved regions.
- Page curl v1: 3D rotation plus shading driven by curl progress; settles back if the hinge reopens before the turn point, and commits past it.

**Exit:** a 5-page mock book turns by folding in the Duo simulator, and the `PostureMachine` tests pass.

### Phase 2: Live story pipeline, parent-driven (≈ 21 h · B) · must-have: live generation

- Speech input (OpenAI Realtime; Apple speech as fallback), typed input, and the parent's/kid's turn toggle (the parent is the default speaker).
- Kid profile (first name, reading level, interests) and the per-book story brief (interests, optional real moment, and an optional free-text "Anything you'd like this story to teach?" that simply goes into the prompt).
- `StoryEngine` with a strict response schema, reading-level limits, a story path planned from the brief (always reaching an ending), and directions that re-plan the path from the page behind (P-04). It leaves surnames, addresses, schools and phone numbers out of the story text.
- The page behind: while a page shows, the next page along the path is fully built. A direction rebuilds it; the page on screen never changes, and only the parent's fold turns the page.
- `StoryBible` and character registry (fixed description plus reference image).
- `Art` (OpenAI images, P-05): locked art style, character references, framing from D9 (16:9 with important content central until G0).
- Kid-safety gate (PRD §8.6 rubric): `omni-moderation-latest` on text, prompts and pictures, plus an LLM rubric check on text and prompts at the kid's reading level, and each category's response (rewrite, redirect, regenerate the picture, placeholder).
- `PagePipeline`: keeps the page behind built, cancels it when a direction arrives, versions each page.
- Persistence in Supabase (rows plus Storage); timing spans for every stage.

**Exit:** a parent makes a 5-page book from a brief in the Duo simulator, by voice and by typing, with one mid-story direction that changes the path. Every fold shows a page that's already built, the story reaches an ending, and a latency table is recorded.

### Phase 3: Living page, Orbis per page (≈ 14 h · A 7, B 7)

- `ReactorWebScene` bridge (bundled JS, Swift event stream) and the `StillPanScene` fallback.
- `SessionController`: warm up on New Book, reconnect with backoff (with a fresh token when one expires or runs out), kill, ask the server to clean up this user's leftover sessions at launch, credit meter.
- `motion-prompt` function (the OpenAI story model reads the page text and still, P-05) and `MotionPromptBuilder`.
- On flip: the per-page sequence; crossfade from still to video; drift guard; audio off while the mic is live.
- Frame tripwire: a sampled frame goes through image moderation, and the page switches back to the still if it's flagged.
- Clip recording: record each page's final animation (method, length and looping from G0) and save it with the page.
- Debug overlay (from the teammate's panel), hidden behind a gesture.

**Exit:** after warm-up, every page animates within 5 s of the flip (p50) and stays on topic for 60 s: an LLM judge scores frames sampled every 10 s at 4 or more out of 5 against the page's text, on 10 pages. Each page's clip is saved. Killing the Reactor session drops cleanly to the still fallback.

### Phase 4: Pop-up (≈ 10 h · A 7, B 3) · must-have

- Layer generation: plate and cutouts (OpenAI images) → chroma key → alpha PNGs, prepared early per page.
- Pop-up renderer: layered SwiftUI with 3D transforms; depth follows the angle; hands over from video to diorama and back. RealityKit is optional.
- Gesture model from D1, wired into `PostureMachine`: the page now showing pops at about 90°, including page 1 as the book opens from its cover.

**Exit:** every generated page pops up at about 90° and folds back flat in the Duo simulator.

### Phase 5: Save and show (≈ 9 h · A 7, B 2) · must-have: exact replay

- Finish: keeping the phone closed for about 1 s (or tapping Save) ends the book, and reopening sooner carries on. Pages without a complete clip are re-animated and recorded first. Generate the title and cover art, and show the cover when `.closed`.
- `BookStore`: save the book with its clips, keep a copy on the device, and show saved books on the bookshelf as covers.
- Show a saved book: `ClipReplayScene` on each page (clips loop as set at G0), with the same curl and pop-up, and no generation calls.

**Exit:** a saved 5-page book shows the identical text, pictures and clips with Reactor switched off and the network disconnected.

> **═══ MVP / demo line: all must-haves done, ≈ 80 h (about 40 h per engineer) ═══**

### Phase 6: Parent controls and sharing (≈ 7 h)
Real-moment tone (calm-tone presets and safety rules). Parent settings and parental gate. PDF export.

### Phase 7: Privacy check (≈ 1 h)
Confirm no audio is ever saved, that only the first name and interests are stored, and that story text carries no surnames, addresses, schools or phone numbers (eval cases). Timing stays in local logs and the debug overlay; there's no third-party crash or analytics service.

### Phase 8: Cut-list features, in order of priority (≈ 18 h)
1. Read-along: `AVSpeechSynthesizer` with word highlighting · 4 h
2. Kid's drawing as the hero: finger-drawing canvas → OpenAI image restyle → character reference · 5 h
3. Reading together: parent co-pilot strip on the text page · 4 h
4. Talking characters · 5 h

### Phase 9: Demo hardening (≈ 8 h · start at least 2 days before the demo)
Golden-path script and book; a saved golden book (exact replay, stored on the device) as the fallback if the network fails; failure drills (no network, Reactor down, moderation blocks something, speech fails); performance pass; 5 rehearsals in a row.

**Total ≈ 114 h.** *(v3 was 109 h. P-03 (iPhone Duo only) removed the non-Duo reader (−2 h), and the readiness fixes added 7 h: splitting the Orbis probe into a go/no-go and comparisons (+4 h), the server access model (+1 h), the kid-safety rubric check (+1 h), and completing clips before saving (+1 h). v2 was 118 h; the 2026-09-26 decisions removed lesson packs and fact-checking (3 h), lesson extras (2 h), and the paywall and crash-reporting work (4 h).)*

## 6. Critical path

`Phase 0.1 hinge probe` → `PostureMachine` → curl → pop-up gesture
`Phase 0.3a Orbis go/no-go` → `0.3b comparisons and clip recording` → `LiveScene` bridge → per-page animation → saved-book replay
`Phase 0.4 and 0.5 probes` → `PagePipeline` → first end-to-end story

The Orbis go/no-go (0.3a) is the riskiest unknown. Start it first, and if it fails, settle its plan B before anything else.

## 7. Cut lines by timeline

| If we have… | Build | Skip |
|---|---|---|
| **About 2 days (≈ 40 h)** | Phase 0 trimmed; Phase 1 (curl, slider allowed); Phase 2 with the story path, the page behind and directions; Phase 3 without drift guard or tripwire (clip recording kept); Phase 4 with two layers; Phase 5 save and exact replay with a basic cover; Phase 9 golden path | Everything else |
| **1 week** | The MVP line + Phase 9 | Phases 6–7, cut-list features |
| **2+ weeks** | Everything except talking characters | Talking characters |

## 8. Testing and verification

- **Unit tests, written first, ≥ 80% coverage on the logic modules:** `PostureMachine`, `MotionPromptBuilder` (the template stays byte-identical), `StoryEngine` decoding and validation, the story path (it always reaches an ending; a direction re-plans from the page behind and never changes the page on screen), reading-level limits, `PagePipeline` cancellation, the kid-safety gate, the `SessionController` state machine against a fake transport, and a `BookStore` round trip (a saved book reloads identically).
- **Server function tests:** each function tested in Deno against recorded fixtures.
- **Eval set:** 30 sessions (parent narration and directions, kid interruptions, mind-changing, scary requests), including briefs that ask the story to teach something. It covers every kid-safety category at each reading level (PRD §8.6), personal details, and 40 labelled utterances for telling narration from directions (S3). Checked for safety, reading level, coherence and reaching a definite ending (S14); passing means 0 misses and false blocks on ≤ 5% of safe pages. Run before every demo.
- **UI:** XCUITest on the iPhone Duo simulator for navigation. Duo postures are tested automatically through a scripted `HingeSource` and the debug slider, because `simctl` can't move the hinge; the real hinge is checked by hand with DeviceHub's hinge slider. Screenshots of both screens: `xcrun simctl io booted screenshot --display=1` (outer) and `--display=3` (inner).
- **Latency:** a timing span per stage, with a p50 table in the debug overlay.

## 9. Demo run-book

**Setup (T-60 min)**
1. Close heavy apps; the load average should be under about 10, or DeviceHub's hinge lags and the simulator stutters (§3).
2. Open DeviceHub with the Duo booted. If the hinge slider is missing, run `defaults write -g com.apple.dt.coredevicepop.useInternalV68ActionBar -bool YES` and reopen DeviceHub.
3. Restore the golden book, which is the network-failure fallback: `scripts/golden-book.sh restore`, then `scripts/golden-book.sh show`.
4. Install the current build (`scripts/sim.sh run`). Check that `scripts/reactor-sessions.sh list` shows 0 open sessions and there's Reactor credit for the demo (PRD §9).
5. Open the Duo with the slider. If the inner screen stays black, click it once to wake it.
6. Pictures and motion prompts use OpenAI (P-05), the same key as the story, so there's no second vendor to top up.

**Rehearsal (T-15 min):** make a book once (about 4 minutes for 8 pages). Then `scripts/golden-book.sh restore` so the golden book, "Maya and the Star Stone" (8 pages), is on the shelf. Mute the Mac, so Orbis sound can't reach the mic. Use a wired connection or a hotspot.

**Live:**
1. **Bookshelf.** Tap New book, fill in the brief (first name, interests), and open.
2. **The story starts itself.** From the brief, the story path is planned and page 1's words land left in about 5 s. The picture lands right about 10 s later and comes alive about 10 s after that. Meanwhile page 2 is built behind it.
3. **Steer.** Type or say a direction ("give the fox a tiny red hat"). Page 1 stays as it is; the page behind is rebuilt in a few seconds (it says "Next page ready. Fold to turn" when it's done).
4. **Turn.** Fold slowly with the slider to about 100°, pause, then open flat. The page behind appears with its picture, and the next one starts building. The in-app panel (triple tap) turns pages if the hinge lags.
5. **The end.** After about 6–8 pages the story reaches its ending, and the banner says "The end. Close the book to finish".
6. **Pop-up.** Fold to about 90° and hold: the scene tilts back and the characters stand up.
7. **Finish.** Tap Finish, or close the Duo. The book gets a title and a painted cover and is saved.
8. **Replay.** Open it from the bookshelf. The same words, pictures and clips play back with no network.

**If something fails**

| Failure | What the audience sees | What to do |
|---|---|---|
| Reactor down or slow | Pictures stay still with a slow pan | Carry on; the book still works. KILL in the debug panel if needed |
| Network down | "Pop! is offline" note | Open the golden book from the bookshelf and demo reading, fold-to-turn and the pop-up |
| Safety gate refuses a line | A gentle note asks for a friendlier direction | Give a gentler line; the 83-case eval set blocks 1 of 47 safe cases (2.1%) and misses 0 of 36 unsafe ones (2026-09-26) |
| Speech fails | A note under the story bar | Type instead |
| Hinge lags | Folds don't turn | Triple-tap for the hinge panel and use Turn and Pop |

**After:** KILL, then `scripts/reactor-sessions.sh list` (expect 0). If needed, `scripts/reactor-sessions.sh kill`.

## 10. Decision log

| # | Decision | Decide by |
|---|---|---|
| D1 | Gesture model for turning vs popping up: the model is recommended in PRD §13, and G0 sets its angles and hold time | G0 |
| D2 | What the latency target means | G0 |
| D3 | Orbis Stable vs Dynamic | G0 |
| D4 | Record per-page clips | ✅ Resolved 2026-09-26 by P-01: required (saved books replay exactly). How, the minimum clip length, looping, and what Save does with incomplete clips: G0 |
| D7 | OpenAI for everything but Orbis: images (`gpt-image-2.5-flare`) and animation prompts (P-05, replacing Gemini), speech-to-text, story, moderation, and `tts` for talking characters and video export. Read-along narration uses Apple's on-device voice | ✅ Confirmed by Brian 2026-09-26; images moved to OpenAI 2026-09-26 (P-05) |
| D8 | Demo date → cut line | ✅ Resolved 2026-09-26: no deadline; build the full scope, including talking characters |
| D9 | How the 16:9 animation fills a portrait page (§3 options) | G0 |

*D5 and D6 were removed on 2026-09-26 (P-02): everything is free.*
