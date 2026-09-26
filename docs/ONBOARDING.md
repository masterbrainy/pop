# Pop! — Onboarding for a new session

*State as of 2026-09-26, `main` @ `b55ece4`. Read [CLAUDE.md](../CLAUDE.md) first (roles, build gate, secrets), then this file. This file describes the app **as built**. Where the PRD or ROADMAP says something different, trust the code and the "Docs that are out of date" section below.*

**Pop! in three sentences.** A parent makes a live picture book for their 3–8 year old on the iPhone Duo (a foldable, simulator only). Each page gets story text on the left and a picture on the right that comes alive as a short Orbis animation. The parent tells or types the story, steers it with directions or tapped choices, and saved books replay exactly as made.

---

## 1. Where things stand

**On `main` and working, with unit tests; live-tested where noted:**
- **Guided setup.** Four picture cards (hero, place, what goes wrong, feeling), each with "Surprise me". Card answers travel as tile ids. The book's own interests override the kid profile's.
- **Page 1 waits for the first prompt.** Nothing is generated until the parent speaks or types. Live-tested.
- **Every page shows only once its picture is done,** page 1 included. The screen shows "Making your first page…" meanwhile. Live-tested: page 1 appeared about 10 s after the prompt.
- **The next page is always built behind the one on screen** (P-04's story path). A direction or a tapped choice rebuilds it; the page on screen never changes. Live-tested.
- **One question per page** with 2–3 tappable choices, "something else" and Skip. The question is gated separately from the page.
- **Page turns.** Fold the Duo to 80° or below and open it past 100°, or tap the corner arrow. Folding to about 90° pops the page up. Closing never finishes the book; the **Finish** button does. Tested on the real hinge path. This is pivot **P-06, still "proposed"** in PIVOTS.
- **Pre-animated page behind.** Record the live page's clip → loop it → the one Orbis session animates the page behind, hidden → at the fold it plays at once. **Unit-tested only; not yet live-tested.**
- **Voice.** OpenAI Realtime, with a pre-minted secret and mic audio buffered until the socket opens. Falls back to Apple's on-device recognizer. **Not tested with real speech.**
- **Reliability:**
  - per-call timeouts;
  - a moderation-flagged picture shows an "imagine" card;
  - Finish is capped at 20 s;
  - re-saving a reopened book keeps its media.

**Needs Brian.**
- **Deploy:** server changes deploy only from Brian's Supabase login. `story-turn` and `art` were deployed after the last merges.
- **Pivot:** decide P-06.

---

## 2. How the app works

```
 iPhone Duo simulator (SwiftUI app)                 Supabase (Brian's project)            Vendors
┌───────────────────────────────────┐            ┌────────────────────────────┐
│ BriefSheet → SetupCardsView        │  HTTPS     │ story-turn  (path/page/title)│──▶ OpenAI gpt-5.4-mini (+nano rubric,
│ BookView → StoryMaker ──PagePipeline├──────────▶│ art         (page/plate/...) │    omni-moderation)
│   BookReader (pages, page behind)  │ anon JWT   │ motion-prompt                │──▶ Gemini gemini-2.5-flash-image
│   LivePageController ─ WKWebView ──┼──WebRTC──┐ │ stt-token · moderate · tts   │    (pictures; back from OpenAI, d55a1a5)
│   RealtimeTranscriber ─────────────┼──WSS──┐  │ │ reactor-token (mint JWT)     │──▶ Reactor Orbis (live video)
└───────────────────────────────────┘        │  │ └────────────────────────────┘
                                   OpenAI Realtime  └──────────────────────────────────▶ Reactor (reactor/visko-orbis-stable)
```

**Making a book:**
1. **New book → guided setup.** `App/Create/BriefSheet.swift` hosts `SetupCardsView`. Answers go into `StoryBrief` (`PopKit/Domain/StoryBrief.swift`). Tapping Go makes an empty book; **no model call yet**.
2. **Empty book.** The left page reads "How does the story begin?…" and the input bar is `StoryInputBar`. The first spoken or typed input starts page 1 (`StoryMaker.submit` → `startOpening` → `runDirection`), and **Orbis starts warming only then** (`startLiveIfNeeded`).
3. **Writing and painting.** `PagePipeline` has two lanes:
   - `writePage`: the story-turn `path` or `page` call. It finishes when the words land.
   - `paint`: art, then the motion prompt, keyed by page id and version, with one retry.

   `PageReadiness` decides when a page is "good to go":
   - page 1 needs words and a stored still;
   - the page behind also needs its motion prompt, or 8 s after its still, whichever comes first;
   - a flagged or late picture counts as ready and shows the imagine card. The deadlines are 45 s for page 1 and 60 s for the page behind.
4. **The page behind.** `BookReader.pendingNext` holds it; `DraftPages` routes results by (id, version).
   - A **direction** (typed or spoken) goes through `TurnQueue`, then `runDirection`, and re-plans from the page behind.
   - A **tapped choice** (`StoryMaker.answer`) does the same, unless the choice follows the planned path.
   - `NextPageStatus` drives the banner ("Rewriting the next page: …") and the corner arrow.
5. **Turning.** `HingeModel` feeds `PostureMachine(config: .closeToTurn)`, which emits `.turnCommitted` → `BookReader.turnForward()`. That opens the page behind only if `canOpenPending` (i.e. its picture is ready); otherwise the parent gets a note. The corner arrow calls the same `turnForward()`.
6. **Live pages** (`App/Scene/LivePageController.swift` and `+Clips.swift`, driven by `PopKit/LiveScene/PreRollPlanner.swift`):
   1. the page on screen goes live;
   2. a 10 s clip is recorded (MediaRecorder in `web/live-scene/src/clip.ts`);
   3. the clip is checked (`ClipFrameSampler`, `ClipVerdict`) and baked into a seamless loop (`LoopBaker`);
   4. the page switches to its loop;
   5. the session pre-animates the page behind, hidden;
   6. at the fold it's revealed at once, or its loop plays.

   The web view never leaves the window (`LiveSceneDock`).
7. **Finish.** `BookView.finish` → `completeClips` (≤ 20 s), with the title and cover generated in parallel. The book is saved by `FileBookStore` in the app's container.

**Reading a saved book.** The bookshelf opens it in reading mode. Each page plays its saved loop (`ClipPlayerView`) with no network, and the question strip shows as text only (`CoPilotStrip`).

---

## 3. File map

| Area | Key files |
|---|---|
| App shell | `App/Shell/AppModel.swift` (books, kid profile), `BookshelfView.swift`, `App/RootView.swift` (automation screens) |
| Creation | `App/Create/StoryMaker.swift` (the orchestrator, about 1,000+ lines), `SetupCardsView.swift`/`SetupCardPage.swift`/`CardListener.swift`, `QuestionStripView.swift`, `StoryInputBar.swift`, `HeroDrawingStep.swift` |
| Book UI | `App/Book/BookView.swift` (banners, corner arrow, Finish), `BookReader.swift`, `SpreadView.swift`, `TextPageView.swift`, `ArtPageView.swift`, `CoverView.swift` |
| Hinge | `App/Hinge/HingeModel.swift`, `DebugHingePanel.swift` (triple-tap), `PopKit/Posture/PostureMachine.swift` (`.standard` = old fold-to-turn, `.closeToTurn` = used), `HingeScript.swift` |
| Live animation | `App/Scene/LivePageController*.swift`, `App/LiveScene/LiveSceneBridge.swift`, `PopKit/LiveScene/*` (SessionController/Machine, PreRollPlanner, LoopBaker, OrbisStill, FrameTripwire), `web/live-scene/src/*` (bundled into `App/LiveScene/Web/`, which is committed) |
| Story logic | `PopKit/Story/*`: PagePipeline, StoryEngine, DraftPages, PageReadiness, NextPageStatus, TurnQueue, QuestionStrip, SetupCards/SetupCatalog, CharacterReferences |
| Speech | `App/Speech/RealtimeTranscriber.swift`, `AppleTranscriber.swift` |
| Networking | `PopKit/Server/API.swift` (wire types), `PopServer.swift` (timeouts), `AnonymousAuth.swift` |
| Server | `supabase/functions/<fn>/index.ts`. Shared code is in `_shared/`: `models.ts` (model ids), `story_prompt.ts`, `story_path*.ts`, `safety.ts`, `input_safety.ts`, `brief_safety.ts`, `question_gate.ts`, `question_plan.ts`, `setup_tiles.*`, `art_request.ts`, `opening_idea.ts`, `rate_limit.ts` (art 20/min, 300/day), `retry.ts`, `reactor_client.ts` |
| Contracts | [docs/CONTRACTS.md](CONTRACTS.md) (wire shapes: keep it in step with API.swift and the zod schemas) |
| Scripts | `scripts/sim.sh`, `golden-book.sh`, `eval/` (paid eval harness), `reactor-sessions.sh`, `probe-orbis.sh`, `dev-token.sh` (the last three need Brian's `.env`) |

---

## 4. Run and test

**Build and test** (paths from the repo root; Xcode 27.1 beta is required):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # or xcode-select it
xcodegen generate --quiet                                              # Pop.xcodeproj is generated from project.yml
xcodebuild -project Pop.xcodeproj -scheme Pop -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build -quiet
(cd PopKit && swift test)                                              # ~411 tests
(cd web/live-scene && npm ci && npm test && npm run typecheck && npm run build)   # the build rewrites App/LiveScene/Web
(cd supabase/functions && deno test --allow-read --allow-env)          # ~389 tests
```

After `xcodegen generate`, `git diff Pop.xcodeproj` should be empty unless you added App files.

**Install and launch on the Duo.** `scripts/sim.sh run` does this for Xcode's device set. By hand:

```bash
xcrun simctl install <duo-udid> build/DerivedData/Build/Products/Debug-iphonesimulator/Pop.app
xcrun simctl launch --terminate-running-process <duo-udid> com.masterbrainy.pop
```

Bitrig keeps its own simulators: add `--set ~/Library/Bitrig/Simulators` to each `simctl` command.

**Scripted end-to-end runs** use Brian's live backend and are paid, about $1–3 per run:

```bash
xcrun simctl launch --terminate-running-process <udid> com.masterbrainy.pop \
  -screen create -setup "hero:kid,place:pond,problem:lost,mood:silly" \
  -storyTurns "an opening idea|wait|fold|choose:2|wait|fold|finish" -logHinge YES
```

- **Steps in `-storyTurns`:**

  | Step | What it does |
  |---|---|
  | plain text | typed input; the first item is the opening prompt |
  | `wait` | waits 20 s |
  | `fold` | waits for the page behind, then turns |
  | `choose:N` | taps choice N |
  | `skip` | skips the question |
  | `pop` | pops the page up |
  | `finish` | finishes the book |
  | `fold during:<text>` | gives a direction, then turns while it's still being written |

- **Results** go to `<app container>/Documents/story.log`: per-step timings, "page 1 shown in N ms", first frames, and `live:` or `pre-roll:` metrics. `hinge.log` records every hinge reading and posture event. Find the container with `xcrun simctl get_app_container <udid> com.masterbrainy.pop data`.
- **App system log** (surfaces Reactor errors):

  ```bash
  xcrun simctl spawn <udid> log show --last 10m --predicate 'subsystem BEGINSWITH "com.masterbrainy"'
  ```

**Hinge.** DeviceHub (`/Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app`) has a slider. Turn it on with this, then restart DeviceHub:

```bash
defaults write -g com.apple.dt.coredevicepop.useInternalV68ActionBar -bool YES
```

For scripted folds, the third-party `hinge` CLI (github.com/artemnovichkov/hinge) works:

```bash
hinge -d <udid> sweep 180 70 0.8
hinge -d <udid> sweep 70 180 0.8   # together: one page turn
```

The simulated hinge follows only when the Mac's load average is under about 10. The Duo reports "closed" below about 85°. Triple-tap in a book for Pop!'s own Turn/Pop panel.

**Fresh Mac:**
1. Install Xcode 27.1 beta at `/Applications/Xcode-beta.app` (an Apple ID download).
2. `xcodebuild -downloadPlatform iOS` (about 8 GB), then `xcrun simctl create "iPhone Duo" <Duo device type> <iOS 27.1 runtime>`.
3. Install `xcodegen`, `deno`, the `supabase` CLI and Node 22+.
4. Create `config/Supabase.local.xcconfig` (git-ignored) with Brian's app-side `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Write the URL as `https:/$()/<ref>.supabase.co`, because `//` starts a comment in xcconfig.
5. Without that file, the app runs offline: the sample book works, but no new pages are made.

---

## 5. Constraints and gotchas

- **One Orbis session per account.** Reactor answers `429 concurrent_sessions_per_model (limit=1)`. When anyone else (Brian's sessions, another simulator) has a book open, your book gets stills only. Confirm with the system log above. Billing is per session-minute from `ready`, idle time included; connecting is free.
- **Deploys go through Brian.** Only his Supabase login can deploy functions. Merging server code isn't live until he deploys.
- **Vendors.** Pictures are on Gemini: P-05 moved them to OpenAI, then `d55a1a5` moved them back, and Gemini credit can run out (HTTP 402). Story, rubric, moderation, motion prompts, speech and TTS are on OpenAI. `_shared/models.ts` is the source of truth.
- **`main`'s history was rewritten once.** If your branch's base commit no longer exists on `main`, rebase with `git rebase --onto origin/main <old-base>` so the old base isn't replayed.
- **Generated files are committed.** `App/LiveScene/Web/*` (from `web/live-scene`) and `Pop.xcodeproj` (from `project.yml`). Rebuild and commit them with their sources.
- **Ownership** ([CLAUDE.md](../CLAUDE.md)):
  - the Builder owns app code, CLAUDE.md, ROADMAP and BUILD_LOG;
  - QA owns REVIEW;
  - Pivots owns PIVOTS and PRD scope.

  Outside contributors (tay, GitHub `dttk23100`) push to `main` or open PRs; the Builder reviews and deploys.
- **Secrets.** Never print or commit keys (see CLAUDE.md). The app-side publishable key is fine in the git-ignored xcconfig.
- **No app test target.** `StoryMaker`, `BookReader` and the view wiring are covered only by scripted simulator runs. Put new logic in PopKit behind tests.
- **Rate limits.** Art is capped at 20 per minute and 300 per day per anonymous user; the Keychain keeps the same user across launches.

---

## 6. Docs that are out of date (as of `b55ece4`)

| Doc | Says | Actually | Owner |
|---|---|---|---|
| CLAUDE.md intro, PRD D1/H1/H3/§7 | Fold past 140° turns; close to finish | Fold ≤ 80° and reopen, or the corner arrow; Finish button (P-06 proposed) | Pivots → Builder |
| PRD §7 steps 1–2, §5 | Page 1 from the brief right away; brief → page 1 text ≤ 5 s | Page 1 waits for the first prompt; pages show only once painted (about 10–15 s) | Pivots |
| PRD S4, C3 | Free-text brief; the question strip is a cut-list item | Guided setup cards; per-page question with choices is built | Pivots |
| BUILD_LOG "How to run" | `scripts/sim.sh`-centred | Also see §4 here (scripted grammar, logs, hinge CLI, Bitrig) | Builder |
| ROADMAP §3 Orbis | Session start-up in minutes; 5 concurrent sessions | Connect about 3.5 s; this account allows **1** Orbis session | Builder |

*This file was written from direct work on the code on 2026-09-26. It hasn't had the planned "fresh reader" check, where a new session answers questions from the docs alone and the answers are graded against the code. Run that check after big changes.*
