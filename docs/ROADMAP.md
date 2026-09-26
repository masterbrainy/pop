# Pop! — Execution Roadmap

*Status: DRAFT v3 · 2026-09-26 · P-01 (parents drive creation; saved books replay exactly; lessons optional) · P-02 superseded (everything is free) · P-03 (iPhone Duo only) · Implements: [PRD.md](PRD.md)*

**Planning assumptions.** Two engineers (Brian plus a teammate) building with Claude Code. Estimates are in **focused hours** and include tests. **There's no deadline (D8, resolved), so we build the full scope in phase order.** The cut lines in §7 are kept only as a fallback. Everything is built and demoed **only on the iPhone Duo simulator in Xcode 27.1 beta**.

---

## 1. Where we are (Day 0, done 2026-09-25)

| Item | Status |
|---|---|
| Xcode 27.1 beta (27A9269) installed and selected; license accepted; first-launch components installed | ✅ |
| Old Xcode 27.0 and every iOS 27.0 simulator image removed | ✅ |
| iOS 27.1 simulator; **iPhone Duo** device boots | ✅ |
| Duo APIs checked in the SDK (see §3) | ✅ |
| Supabase CLI logged in and linked to the project | ✅ |
| API keys (Reactor, Gemini, OpenAI): each returns HTTP 200, stored in Supabase secrets and the git-ignored `supabase/functions/.env` | ✅ |
| App-side Supabase URL and publishable key in git-ignored `config/Supabase.local.xcconfig` | ✅ |
| Private GitHub repo `masterbrainy/pop` | ✅ |
| Claude Code ↔ Xcode tools (`xcrun mcpbridge`) | ✅ |
| Claude Code ↔ iOS Simulator panel attached to the **iPhone Duo** (466×678 pt reported at first boot; posture to be confirmed in Phase 0.1) | ✅ |
| Sibling sessions running: Review & QA and Pivots & Ideas (roles in `CLAUDE.md`) | ✅ |
| **Build gate:** Brian verifies the setup and says to start | ⏳ |

## 2. Architecture at a glance

```
┌──────────────────────────── iOS app (SwiftUI, iOS 27.1) ────────────────────────────┐
│  Posture          Book UI                    Story pipeline (actor)    Living page  │
│  HingeSource ──▶  SpreadView (Arrangement)   SpeechInput ─▶ StoryEngine LiveScene    │
│  PostureMachine   TextPage | ArtPage ◀────── PagePipeline ─▶ Art     ◀─ (WKWebView + │
│  (pure, tested)   PageCurl · PopUp · Cover   StoryBible · Moderation    Reactor JS)  │
│                   Bookshelf · SingleReader   Narration                 StillPan fb   │
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
| `HingeSource` | Emits posture updates `(status, angle)`. Two versions: Duo (`onHingeChange`) and a debug slider. iPhone Duo only (P-03) | — |
| `PostureMachine` | Pure function from a stream of angles to effects: curl progress, turn committed or cancelled, pop depth, closed | `HingeSource` values |
| `PagePipeline` | Per page: input → text → art → layers → animation prompt. Prepares the next page early; cancels work when a direction changes the page | StoryEngine, Art, Moderation |
| `StoryEngine` | One LLM call per turn. Input: the story brief (interests, optional real moment, optional "teach something" note), the bible, and the parent's or kid's words (spoken or typed) or a "You continue" tap. Structured output: `append / new_page / revise_current`, text, art prompt, bible and direction updates, parent question | `story-turn` function |
| `Art` | Gemini page illustration (16:9, important content kept central), background plate, character cutouts, cover | `art` function |
| `MotionPromptBuilder` | Builds the Orbis prompt for **one page only** from a fixed template (below) | `motion-prompt` function |
| `LiveScene` | Protocol: `prepare(image:prompt:)`, `start()`, `stop()`, event stream. Implementations: `ReactorWebScene` (also records each page's clip), `StillPanScene` (fallback) and `ClipReplayScene` (plays a saved page's recorded clip) | Reactor JS SDK |
| `SessionController` | Orbis session lifecycle: warm-up, token, reconnect with backoff, kill, server-side cleanup of stray sessions, credit meter | `reactor-*` functions |
| `BookStore` | Saves a finished book (rows, pictures, layers, clips) and keeps a copy on the device, so a saved book shows exactly and works offline | Supabase |

**Per-page animation sequence (PRD P3–P5).** On page shown (fully open):
`reset → set_image(page still) → set_prompt(page motion prompt) → wait for conditions_ready → start`. The still stays on screen until the first frames arrive, because the first chunk after start contains none. A drift guard re-anchors, or pauses and holds the frame, after *T* seconds, where *T* comes from the Phase 0 spike. On flip, the same sequence runs for the next page. Orbis audio is off during creation. While the final version of a page plays, its clip is recorded (length set at G0) and saved with the page. When a saved book is shown, `ClipReplayScene` plays that clip instead and no Reactor session is needed.

**Motion prompt template.** This applies the teammate's continuity lesson. `SCENE` (from this page's text plus its illustration) and `CAMERA` stay identical within the page, and only one gentle motion clause varies:
`"The same {SCENE}, the same {CAMERA: locked-off, still}. {ONE GENTLE MOTION CLAUSE}. Nothing new enters the scene. Continuous slow motion, no cuts."`

## 3. Platform facts

### iPhone Duo APIs, verified in the iOS 27.1 SDK

These were checked by reading the SDK's `SwiftUICore` interface file on 2026-09-25.

| API | Signature | Use in Pop! |
|---|---|---|
| Hinge | `func onHingeChange(isEnabled: Bool = true, _ action: @escaping (_ oldContext: DeviceHingeContext, _ newContext: DeviceHingeContext) -> Void) -> some View` · `DeviceHingeContext.hinge: DeviceHinge?` (nil when there's no hinge) · `DeviceHinge.status`: a **struct with static members** `.closed / .partiallyOpen / .fullyOpen`, **not an enum**, so compare with `==`, and any `switch` needs a `default` · `DeviceHinge.angle: Angle` (UIKit's `UIHinge.angle` is a `CGFloat` in **radians**) · **The rate and granularity of angle updates are "system policy"** (`UIHinge.h`), so don't rely on update frequency or precision | `status` → mode (book or cover); `angle` → curl progress and pop depth, **animated smoothly between samples** |
| Two-pane layout | `ArrangementView { primary } secondary: { secondary }`: both are `@ContentBuilder` closures, and there are only ever two panes · `.arrangementViewStyle(.split / .overlay)` · `.splitArrangementLayoutRatio(_:)` | The spread: primary = text page, secondary = art page |
| Reserved regions | `GeometryProxy.reservedRegions(kind: .occlusion / .division, options: [.includeInactive], layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]`, each with `frame`, `margins`, `isActive` | Pad text and position the art away from the fold (`.division`) and camera (`.occlusion`). *These kind meanings are inferred from the names.* |
| UIKit versions | `UIHingeInteraction`, `UIArrangementViewController` | Not needed (the app is SwiftUI) |
| Cover display | **No dedicated API in the SDK** | `.closed` → cover view. Verify how the simulator shows the outer screen (Phase 0) |

### Reactor Orbis, from Reactor's docs and the teammate's starter

- There is **no Swift SDK**. Stable documents JavaScript (`@reactor-team/js-sdk` 3.x) and Python; Dynamic also lists raw WebRTC. So we host the JS SDK inside a `WKWebView`, bundled into the app rather than loaded from the web.
- `set_image` works only before `start`; changing it needs `reset` + `start`. `set_prompt` works mid-run and takes effect at the next ~1.8 s chunk. The first chunk after `start` has no frames.
- Session startup takes **minutes**. Tokens come from `POST https://api.reactor.inc/tokens` (up to 6 h, capped by a maximum session count). A failed connect can leave a session running that only the API key can delete.
- **Stable:** 832×480 at 18 fps native, delivered at up to 4K, $0.582/min. **Dynamic:** 640×368, $1.254/min, can change resolution live, sessions up to ~60 min. Whether billing counts from connection or from generation is **unclear**.
- Input images work best at 16:9; other shapes get squashed. We generate 16:9 art with the important content in the centre and crop it to the right page.

### Other facts that affect the design

- Apple's Vision background removal (`VNGenerateForegroundInstanceMaskRequest`) reportedly **doesn't run in the Simulator** (Apple Developer Forums). So pop-up layers are generated directly: a background plate plus character cutouts on a flat colour that Core Image keys out.
- OpenAI text-to-speech **returns no word timings**, so read-along uses `AVSpeechSynthesizer`'s `willSpeakRangeOfSpeechString` callback.
- OpenAI Realtime supports transcription-only sessions, with **short-lived client secrets minted by our server**, so the app never holds the key.

## 4. Reusing the teammate's starter (with permission)

| Source in `orbis-hackathon-starter` | Becomes in Pop! |
|---|---|
| `app/api/token/route.ts` | `supabase/functions/reactor-token` (near-direct port to Deno) |
| `app/api/sessions/route.ts` | `supabase/functions/reactor-sessions` (list and clean up stray sessions) |
| `hooks/use-orbis-session.ts` | `web/live-scene/` bridge: connect and reconnect with backoff, wait for `conditions_ready`, a single prompt path with a chunk-stamped log, event handling, kill and cleanup |
| `lib/orbis.ts` | Message unwrapping, fallback for the chunk-index field name, credit constants |
| `lib/scene.ts` | The pattern behind `MotionPromptBuilder` (fixed scene and camera, one changing clause) |
| `components/status-panel.tsx` | Pattern for the in-app debug overlay: status, chunk, prompt log, errors, credit meter, KILL |
| README flow (image model → image-grounded prompt → Orbis start image) | The per-page pipeline, with Gemini doing both steps |

## 5. Phases

Tracks: **A** = device and UI · **B** = AI and backend. The two tracks meet at the `PageContent` model and the `LiveScene` protocol, which are defined in Phase 0 so both can work against mocks.

### Phase 0: Probes and foundations (≈ 13 h · A 7, B 6)

| Task | Track | Est | Answers |
|---|---|---|---|
| 0.1 Hinge probe screen: show `status` and `angle` live while using the simulator's fold controls | A | 2 h | Is the angle continuous? How often does it update? How is `.closed` / the cover shown? |
| 0.2 Spread probe: `ArrangementView` split, and the reserved regions drawn as overlays | A | 1 h | Page sizes and aspect ratio, and where the fold and camera are |
| 0.3 Orbis in iOS probe: `WKWebView` + bundled JS SDK + token → video playing in the Duo simulator | A | 4 h | Warm-up time, time from `reset` to first frame, drift after 30 and 60 s, Stable vs Dynamic on 3 picture-book images, **how to record each page's clip** (required: saved books replay exactly; try in-page recording first, then native capture of the web view) |
| 0.4 Gemini probe: page art with a character reference at 16:9, plus plate and cutout edits | B | 2 h | p50 latency, character consistency, how well the cutouts key out |
| 0.5 Speech probe: Mac mic → simulator → OpenAI Realtime transcription using a short-lived secret | B | 2 h | End-of-speech detection, latency, whether Apple on-device speech works in the simulator |
| 0.6 Backend skeleton: Supabase project, schema and access rules, `reactor-token`, `reactor-sessions`, stub functions, secrets | B | 2 h | — |

**Gate G0:** decide D1 (gesture model) and D3 (Stable or Dynamic); settle how clips are recorded and how long each page's clip is (D4); fix the latency budget; freeze the `PageContent` and `LiveScene` contracts.

### Phase 1: Book shell and hinge (≈ 8 h · A) · must-have: curl

- App skeleton and navigation: Bookshelf → New Book → Book.
- Domain models (`Book`, `Page`, `Character`, `StoryBible`, `KidProfile`, `StoryBrief`) and mock data.
- `HingeSource` (Duo, slider, none) and **`PostureMachine` built test-first**, driven by scripted angle sequences. These include **sparse, irregular and jumpy updates** (the update rate is system policy), and the curl smooths between samples.
- `SpreadView`: left text page, right art page (still only for now), padded for reserved regions.
- Page curl v1: 3D rotation plus shading driven by curl progress; springs back if released early, commits past the threshold.

**Exit:** a 5-page mock book turns by folding in the Duo simulator, and the `PostureMachine` tests pass.

### Phase 2: Live story pipeline, parent-driven (≈ 20 h · B) · must-have: live generation

- Speech input (OpenAI Realtime; Apple speech as fallback), typed input, and the parent's/kid's turn toggle (the parent is the default speaker).
- Kid profile (first name, reading level, interests) and the per-book story brief (interests, optional real moment, and an optional free-text "Anything you'd like this story to teach?" that simply goes into the prompt).
- `StoryEngine` with a strict response schema, reading-level limits, page breaks, parent directions (add or change, carried into later pages), "You continue", and a revise-current action.- `StoryBible` and character registry (fixed description plus reference image).
- `Art` (Gemini): locked art style, character references, 16:9 with important content central.
- Moderation gate on text, prompts and images; safe fallback lines.
- `PagePipeline`: prepares the next page early, cancels work on revision, versions each page.
- Persistence in Supabase (rows plus Storage); timing spans for every stage.

**Exit:** a parent makes a 5-page book from a brief in the Duo simulator, by voice and by typing, using at least one direction and one "You continue". Pages fill with text and then art, and a latency table is recorded.

### Phase 3: Living page, Orbis per page (≈ 14 h · A 7, B 7)

- `ReactorWebScene` bridge (bundled JS, Swift event stream) and the `StillPanScene` fallback.
- `SessionController`: warm up on New Book, reconnect with backoff, kill, clean up stray sessions at launch, credit meter.
- `motion-prompt` function (Gemini reads the page text and still) and `MotionPromptBuilder`.
- On flip: the per-page sequence; crossfade from still to video; drift guard; audio off while the mic is live.
- Frame tripwire: a sampled frame goes through image moderation, and the page switches back to the still if it's flagged.
- Clip recording: record each page's final animation (method and length from G0) and save it with the page.
- Debug overlay (from the teammate's panel), hidden behind a gesture.

**Exit:** every page animates within 5 s of the flip and stays on topic for 60 s, and each page's clip is saved. Killing the Reactor session drops cleanly to the still fallback.

### Phase 4: Pop-up (≈ 10 h · A 7, B 3) · must-have

- Layer generation: plate and cutouts (Gemini) → chroma key → alpha PNGs, prepared early per page.
- Pop-up renderer: layered SwiftUI with 3D transforms; depth follows the angle; hands over from video to diorama and back. RealityKit is optional.
- Gesture model from D1, wired into `PostureMachine`.

**Exit:** every generated page pops up at about 90° and folds back flat in the Duo simulator.

### Phase 5: Save and show (≈ 8 h · A 6, B 2) · must-have: exact replay

- Finish: closing the phone (or tapping Save) ends the book; generate the title and cover art; show the cover when `.closed`.
- `BookStore`: save the book with its clips, keep a copy on the device, and show saved books on the bookshelf as covers.
- Show a saved book: `ClipReplayScene` on each page, with the same curl and pop-up, and no generation calls.

**Exit:** a saved 5-page book shows the identical text, pictures and clips with Reactor switched off and the network disconnected.

> **═══ MVP / demo line: all must-haves done, ≈ 73 h (about 37 h per engineer) ═══**

### Phase 6: Parent controls and sharing (≈ 7 h)
Real-moment tone (calm-tone presets and safety rules). Parent settings and parental gate. PDF export.

### Phase 7: Privacy check (≈ 1 h)
Confirm no audio is ever saved and that only the first name and interests are stored. Timing stays in local logs and the debug overlay; there's no third-party crash or analytics service.

### Phase 8: Cut-list features, in order of priority (≈ 18 h)
1. Read-along: `AVSpeechSynthesizer` with word highlighting · 4 h
2. Kid's drawing as the hero: finger-drawing canvas → Gemini restyle → character reference · 5 h
3. Reading together: parent co-pilot strip on the text page · 4 h
4. Talking characters · 5 h

### Phase 9: Demo hardening (≈ 8 h · start at least 2 days before the demo)
Golden-path script and book; a saved golden book (exact replay, stored on the device) as the fallback if the network fails; failure drills (no network, Reactor down, moderation blocks something, speech fails); performance pass; 5 rehearsals in a row.

**Total ≈ 107 h.** *(v2 was 118 h. The 2026-09-26 decisions removed lesson packs and fact-checking (3 h), lesson extras (2 h), the paywall and crash-reporting work (4 h), and the non-Duo reader (2 h, P-03).)*

## 6. Critical path

`Phase 0.1 hinge probe` → `PostureMachine` → curl → pop-up gesture
`Phase 0.3 Orbis probe` (including clip recording) → `LiveScene` bridge → per-page animation → saved-book replay
`Phase 0.4 and 0.5 probes` → `PagePipeline` → first end-to-end story

The Orbis probe (0.3) is the riskiest unknown. Start it first.

## 7. Cut lines by timeline

| If we have… | Build | Skip |
|---|---|---|
| **About 2 days (≈ 40 h)** | Phase 0 trimmed; Phase 1 (curl, slider allowed); Phase 2 with the brief, directions and "You continue"; Phase 3 without drift guard or tripwire (clip recording kept); Phase 4 with two layers; Phase 5 save and exact replay with a basic cover; Phase 9 golden path | Everything else |
| **1 week** | The MVP line + Phase 9 | Phases 6–7, cut-list features |
| **2+ weeks** | Everything except talking characters | Talking characters |

## 8. Testing and verification

- **Unit tests, written first, ≥ 80% coverage on the logic modules:** `PostureMachine`, `MotionPromptBuilder` (the template stays byte-identical), `StoryEngine` decoding and validation, directions and "You continue" (a direction carries into later pages), reading-level limits, `PagePipeline` cancellation, the moderation gate, the `SessionController` state machine against a fake transport, and a `BookStore` round trip (a saved book reloads identically).
- **Server function tests:** each function tested in Deno against recorded fixtures.
- **Eval set:** 30 sessions (parent narration and directions, "You continue", kid interruptions, mind-changing, scary requests), including briefs that ask the story to teach something, checked for safety, reading level and coherence. Run before every demo.
- **UI:** XCUITest on the iPhone Duo simulator for navigation. A Duo posture checklist run through Claude's simulator tool, with a screenshot per posture.
- **Latency:** a timing span per stage, with a p50 table in the debug overlay.

## 9. Demo run-book

- **T-60 min:** launch and open a New Book to warm Orbis. The overlay should show 1 open session, status ready and the credit meter running, with enough Reactor credit left for the demo (PRD §9 credit budget).
- **T-15 min:** a rehearsal pass; headphones or muted speakers so the animation's sound doesn't reach the mic; a wired connection or a hotspot.
- **Live:** follow the script. If Reactor fails, the still fallback takes over automatically. If the network fails, show the saved golden book.
- **After:** KILL, then clean up stray sessions; confirm 0 open sessions on the account.

## 10. Decision log

| # | Decision | Decide by |
|---|---|---|
| D1 | Gesture model for turning vs popping up | G0 |
| D2 | What the latency target means | G0 |
| D3 | Orbis Stable vs Dynamic | G0 |
| D4 | Record per-page clips | ✅ Resolved 2026-09-25 by P-01: required (saved books replay exactly). How, and the clip length: G0 |
| D7 | Gemini covers images only; OpenAI keeps speech, story and narration | Assumed; confirm now |
| D8 | Demo date → cut line | ✅ Resolved 2026-09-25: no deadline; build the full scope, including talking characters |

*D5 and D6 were removed on 2026-09-26 (P-02): everything is free.*
