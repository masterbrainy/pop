# Pop! — Improvement audit

*An outside review of `main` @ `5e0d4e5`, rebased on `eba14be` (2026-09-26, after P-04, the R-31 fix, QA's R-35–R-37 and the working hinge). Read-only: no code was changed. Priorities, in order: **latency**, **demo reliability**, **output quality**; then cost and stack logistics. Nothing was off the table, including the premise. Findings already in [REVIEW.md](REVIEW.md) (R-01 to R-37) aren't repeated unless something new was found; related R-IDs are named.*

**How to read this.** Each item says what's wrong, where (file:line), the fix, a rough effort, and **what was checked versus estimated**. Latency numbers other than the Phase 0 probes (Gemini 5.0 s; Orbis prepare 1.6 s plus first frame 4.8 s; one story-model call of 2.3 s from the timing fixture in `c20e90f`) are estimates, because no end-to-end latency table exists yet (IMP-03). Everything was reviewed against the post-P-04 PRD. Where the code hasn't caught up with P-04, the item says whether it still applies.

---

## Start here: five things, in order

| # | Item | Why now | Effort |
|---|---|---|---|
| 1 | [IMP-01](#imp-01) Results are applied by page index onto an old copy of the book | Clips and pop-up layers get silently wiped; folding mid-turn strands the parent on a blank page. Both paths are P-04's core flow | ~6 h |
| 2 | [IMP-02](#imp-02) The R-31 fix makes the next input wait for art | A direction spoken during a turn waits ~10–15 s before its text even starts | ~3 h |
| 3 | [IMP-03](#imp-03) Measure before optimising | No PRD §5 latency target can pass or fail on evidence today; the order of everything below depends on it | ~3 h |
| 4 | [IMP-04](#imp-04) Animate the page behind before the fold (record, then loop) | The only way to meet "fold → animation ≤ 5 s" with one session, and it is exactly P-04's "gentle, repeating motion" | ~12–16 h |
| 5 | [IMP-05](#imp-05) Make the fold reliable on stage | Hinge readings are sparse, so a quick fold can miss the turn; script the folds | ~2–3 h |

---

## P0: fix first

<a id="imp-01"></a>
### IMP-01 · Results are applied by page index onto an old copy of the book · HIGH · ~6 h · related R-35(a)
- **What.**
  - `StoryMaker.swift` starts each turn with `reader.book` as it is at that moment. The reply's `book.with(bible:)` is built from that copy, and `BookReader.update(book:)` (`BookReader.swift:76-80`) keeps the copy's version of every page. So a clip (`attachClip`), pop-up layers (`prepareLayers`) or a still (`storeStill`) that landed while the turn was running is **reverted**.
  - Folding while a `new_page` turn is running: `turnForward` appends a blank page N+1. The reply then sets `pendingNext.index = N+1`, and the next fold is refused because the current page is empty (`BookReader.swift:58`).
  - `updatePage` routes by index and prefers `pendingNext` (`:95-100`), so the page on screen never gets its still, even after the parent speaks again. The stale draft reappears later as the wrong next page.
  - `stillReady` and `motionReady` carry no page id or version (`PagePipeline.swift:10-11`).
- **Impact.** Lost clips add about 17 s each at Finish (IMP-13). Lost layers turn the pop-up into the flat card. The stranded blank page breaks the demo on any eager fold. How often clips and layers are lost is unmeasured.
- **Why it matters more after P-04.** "The page behind is always being built while the parent folds" is P-04's normal flow, and it is exactly this race.
- **Fix.**
  1. Address everything by **(page id, version)**.
  2. A reply applies the bible, plus text for a draft whose version still matches. Media merges per page ("same id and version → keep any media already there"), never by replacing whole pages.
  3. Put `pageId` and `version` on every pipeline event and drop stale ones.
  4. Move this reducer (`BookReader` plus `StoryMaker.apply`) into PopKit as a pure `CreationSession` so it runs under `swift test`. Today the App target has no tests, and this is where the race bugs live.
  5. Stopgap (about 30 min): block the fold while a turn that may produce the page behind is still running, and show "finishing this page…".
- **Confidence.** Checked: the code. Both sequences were reproduced in a scratch harness that compiles the unmodified `BookReader.swift` against PopKit, and a second agent confirmed them by reading the code. How often each happens is unmeasured.

<a id="imp-02"></a>
### IMP-02 · The R-31 fix makes the next input wait for art · HIGH · ~3 h
- **What.** `f583e4f` queues inputs and runs the merged queue only after `for await event in events` finishes (`StoryMaker.runTurn`). That loop covers the **whole** pipeline run: story-turn, then art, then motion-prompt. So a direction spoken while page art is being made has its text started only after art (about 5 s) plus motion-prompt (about 3 s, estimated) plus the story turn.
- **Fix.** Split the run into two lanes:
  1. A **text lane**, one story-turn at a time with merged inputs, released as soon as the text reply is applied.
  2. An **art lane** keyed by (page id, version) that doesn't block the text lane. It restarts only when the art prompt actually changed.
  3. Debounce the start of art by about 1–2 s after a text reply when another input is already queued. A cancelled Swift task doesn't stop the edge function, so every superseded image is still billed and still counts toward the 20/min art limit (IMP-14).
- **Confidence.** Checked: the code in `f583e4f`. The seconds are estimates.

<a id="imp-03"></a>
### IMP-03 · Measure before optimising · MEDIUM · ~3 h
- **What.** `PagePipeline` times only three server calls. There are no timestamps for speech end, text shown, still shown, flip, prepare or first frame, and every PRD §5 target is measured from those points. The server already returns `timings {modelMs, safetyMs}`, and the app decodes them and discards them (`API.swift:190`). BUILD_LOG has no latency table, though the Phase 2 exit requires one.
- **Fix.**
  1. Give each turn a trace id and record monotonic stamps at: speech stopped, final transcript, request sent, text shown, still stored, motion ready, prepare done, first frame, fold.
  2. Log the server's own timings next to them.
  3. Show p50 and p90 against the PRD targets in the debug overlay.
  4. Run a scripted 5-page book three times and commit the table to BUILD_LOG before optimising anything else.
- **Confidence.** Checked: the gaps, by grep.

<a id="imp-04"></a>
### IMP-04 · Animate the page behind before the fold: record, then loop · HIGH · ~12–16 h · related R-36, R-05
- **What.** P-04's PRD admits that "only the new page's animation starts after the fold". Probe 0.3a measured that at prepare 1.6 s plus first frame 4.8 s, so **about 6.4 s** of still after every fold, above P3's ≤ 5 s. The 4.8 s is mostly built into the model: the first chunk after `start` has no frames (`orbis.ts:30`). Tuning won't fix it; only starting earlier will.
- **What this adds to R-36.** R-36 says the page behind can't be animated in advance with one session, and proposes a second warm session at about twice the credit. It can be done with one session, as follows.
- **Idea.** P-04 now wants each page's animation to be *a gentle, repeating motion that doesn't move the plot on*. That's a loop. So:
  1. When a page goes live, capture a ~10 s clip, then **loop the local clip** on screen (the saved-book player already does this).
  2. Use the now-free session to `reset → set_image → set_prompt → start` **the page behind**, and record its clip with nobody watching.
  3. At the fold, the page behind plays its finished clip at once (0 s). The loop also acts as the drift guard, since the child sees the first, most on-model seconds, and it ends the idle live generation of a page nobody needs.
- **Clip source.** The bundled SDK 3.0.2 already has server-side `requestClip(durationSeconds)` and `downloadClipAsFile` (`index.d.ts:433-485, 837-846`; docs.reactor.inc/concepts/recordings: *"Captures the last durationSeconds of the live session"*). That's independent of whether the web view is on screen, and it can grab a clip after the fact (up to 5 min back). Spend 30 minutes on the next paid probe to confirm Orbis has recording enabled and to check clip resolution and size. Keep `MediaRecorder` as the fallback.
- **Must-haves.**
  - A clip carries (page id, version). Today a clip recorded before a revision is attached to the revised page, which then never animates (`StoryMaker.attachClip` looks up by id only; `LivePageController.swift:160` compares against its own stale copy). A page behind that is rebuilt after a direction must drop its old clip.
  - The frame tripwire checks at 3 s and then every 15 s (`FrameTripwire.swift:18-19`), but a clip is 10 s long, so most of every saved clip is never moderated. And `hold()` never clears a clip that's already attached. Check 3–5 frames sampled from the finished clip before attaching it.
- **Cheaper first steps (~2 h).**
  - Send Orbis a downscaled 832×480 JPEG instead of the stored 1344×768 PNG (`StillImageLoader.swift:20`). Measured on sample art: 1.8 MB versus 175 KB. That's about 1.4 s versus 0.14 s at 10 Mbit/s uplink.
  - Split prepare so the upload and `set_image` start when the still lands, and `set_prompt` plus `start` run when the motion prompt lands.
- **Confidence.** Checked: the probe numbers (ROADMAP §3), the SDK types, the Reactor docs, the file sizes, and the clip/version bug by tracing the code. Not built or run. Whether Orbis has recording enabled is unverified.

<a id="imp-05"></a>
### IMP-05 · Make the fold reliable on stage · MEDIUM · ~2–3 h · updated for `eba14be`
- **What.** Since `eba14be`, the DeviceHub hinge works when the Mac isn't overloaded: the app moves to the inner spread, and DeviceHub's 3D model shows the fold. Two risks remain (ROADMAP §3):
  - **Hinge updates are sparse.** About one reading arrives per status change or pause, so a fold to 103° may arrive only as 154°. `PostureMachine` turns the page at ≤ 140°, so a quick, smooth fold can be missed and only a fold with a pause turns reliably.
  - **Load.** At load averages of 60–400 the Duo never reaches the commanded angle.
- **Fix.**
  1. Drive the demo's folds from a script rather than a hand on the slider. `artemnovichkov/hinge` (MIT, needs Xcode 27.1) injects the hinge event from the command line (`hinge sweep 180 120 2`, `hinge 90`; https://github.com/artemnovichkov/hinge). A sweep with a short pause at each step guarantees a reading lands past the turn point. Verify with the new `-logHinge`.
  2. Add presenter hotkeys (T turn, P pop, C close, O open) that play `HingeScript` moves, as a backup that doesn't depend on hinge readings. This also avoids R-26's flapping.
  3. Put `load average < 10` in the preflight check (IMP-15), and don't build during the demo.
  4. Optionally mirror serve-sim's 3D Duo view (EvanBacon/serve-sim PR #156) to the projector if DeviceHub's own window is too small to read.
- **Confidence.** Checked: ROADMAP §3 as of `eba14be`, and that both tools exist (via `gh`). The CLI hasn't been tested on this Mac.

---

## Latency

<a id="imp-06"></a>
### IMP-06 · Story model output: don't carry the "re-emit everything" pattern into P-04's path planner · HIGH · ~3 h (schema), +8–10 h (streaming)
- **What.**
  - Every `story-turn` reply re-emits the entire bible: title, setting, every character with its description, and every direction (`_shared/story_schema.ts:12-47`).
  - There's no streaming and no `max_completion_tokens` (`openai_chat.ts:26-40`).
  - The safety gate starts only after the whole reply is parsed (`story_turn.ts:139-140`).
  - Output grows with the book, and the model can rewrite the "fixed" character descriptions on every turn, which works against S6.
  - Character **ids are never shown to the model** (`story_prompt.ts:21-24`), yet ids are the only merge key that keeps a `referencePath` (`story_turn.ts:43-54`). A stored reference would be lost on the next turn (see IMP-18).
- **P-04.** A path planner that re-emits the whole path on every direction would make this worse, and "brief → page 1 text ≤ 5 s" now depends on it.
- **Fix.**
  1. Output only changes: a nullable `bibleDelta` with new characters and new directions. Existing characters, their ids and descriptions are owned by the server and never change.
  2. Plan the path as a short outline (one line per page). Write full text only for the page being built, and cap output tokens.
  3. For page 1, return page 1's text first and plan the rest in the background.
  4. Later: stream the reply and start the safety gate on the page text as soon as that field closes.
- **Confidence.** Checked: the code and OpenAI's model pages (`gpt-5.4-mini` supports streaming and defaults to no reasoning). Token counts and savings are estimates.

<a id="imp-07"></a>
### IMP-07 · The motion prompt is a separate serial hop that fails with no fallback · MEDIUM · ~3 h
- **What.** `PagePipeline.swift:177-190` runs art, then motion-prompt. That function downloads the still that was just uploaded, calls Gemini with it, and runs the safety gate at the strictest level (`motion-prompt/index.ts:29-55`). On "unsafe" or any error it throws, and the page **never animates**: `StoryMaker.animate` requires `motionPrompts[page.id]`. `MotionPromptBuilder.defaultMotion` covers only an empty clause.
- **P-04.** This matters for page 1 and for a page behind rebuilt just before a fold. For a page behind built early, it's off the critical path.
- **Fix.**
  1. Have `story-turn` also emit one gentle `motion` clause, gated in its existing safety call.
  2. Start Orbis with `ensureStyleLockedScene(artPrompt)` plus that clause as soon as the still lands.
  3. Run the image-grounded motion-prompt in the background, and apply it with `setPrompt` mid-run (it takes effect at the next ~1.8 s chunk) if it differs.
  4. On any motion-prompt failure, fall back to the template, not to nothing. The art prompt already passed the gate at the child's reading level.
- **Confidence.** Checked: the code. The 2–5 s is an estimate.

<a id="imp-08"></a>
### IMP-08 · Speech: the first words are clipped, and end-of-turn detection is slow · MEDIUM · ~2–4 h
- **What.**
  - Each mic tap mints a token (Supabase sign-in check, `stt-token`, then OpenAI client secret) **before** the socket and mic start (`RealtimeTranscriber.swift:27-31`), so the first second or two of speech is lost.
  - Voice detection waits 700 ms of silence (`openai_audio.ts:54`) and then transcribes the whole turn; the turn is sent only on `transcription.completed`.
  - Any Realtime `error` event, including non-fatal protocol errors, turns the mic off (`StoryMaker.swift:157-159`).
  - The Apple fallback that ROADMAP Phase 2 promises is used only when the server is nil.
- **Fix.**
  1. Pre-mint the secret in `begin()`, start buffering mic audio at once, and flush it when the socket opens.
  2. Treat only a closed socket as fatal, with one silent reconnect.
  3. A/B `gpt-live-transcribe` at delay `low` (it streams words as they're spoken, and the app decides where a sentence ends) against today's model, using FileLog timestamps on 20 recorded utterances.
  4. Don't raise the silence threshold: the R-31 queue now merges split sentences.
- **Correction to an earlier claim.** `gpt-4o-transcribe` *is* supported on the GA `/v1/realtime` endpoint the app uses; "not supported" applies only to the legacy transcription-sessions endpoint.
- **Confidence.** Checked: the code and OpenAI's realtime-transcription guide. Latency not measured; probe 0.5 has no recorded result.

<a id="imp-09"></a>
### IMP-09 · Every server call makes 2–3 extra sign-in and database round trips · LOW · ~2 h
- **What.**
  - `auth.ts:29` calls `getUser()`, a network call, on every request, even though the gateway already verified the JWT (`verify_jwt` is on for everything except `reactor-sessions`).
  - `art` makes two serial rate-limit RPCs (`art/index.ts:63-65`).
  - The first New Book also pays for the anonymous sign-up.
- **Fix.**
  1. Decode `sub` from the already-verified JWT locally.
  2. Merge art's per-minute and daily checks into one RPC.
  3. Sign in at app launch.
  4. Make `AnonymousAuth`'s refresh single-flight, and sign up again only when GoTrue rejects the refresh token (400/401), not on a timeout or 5xx (`AnonymousAuth.swift:86-100`).
- **Confidence.** Checked: the code. The savings (about 0.05–0.3 s per call) depend on the unknown region layout.

---

## Demo reliability

<a id="imp-10"></a>
### IMP-10 · No timeouts or retries anywhere, and a flagged picture always breaks its page · HIGH · ~5 h (placeholder fix: 15 min)
- **What.**
  - There's no `AbortSignal` in any edge function fetch (`openai_chat.ts:26`, `gemini_client.ts:51,95`, `openai_moderation.ts:25`, `reactor_client.ts`), and no request timeout in the app (`URLSession.shared`, `PopServer.swift:10-22`). A hung call shows "Painting…" for up to 60 s, and an Orbis prepare can hang for up to 300 s (`scene.ts:11`).
  - Gateway 5xx/401 bodies aren't envelopes, so they become "Pop! sent something unexpected", and the 401 refresh-and-retry never runs.
  - **Deterministic bug:** when image moderation flags twice, `art` returns `path ""` and `placeholder: true`. `runArtAndMotion` ignores `placeholder` and calls motion-prompt with `stillPath ""`, which fails its schema (`motion-prompt/schema.ts:9`). The child sees "Painting…" forever, and the parent sees a misleading error.
- **Fix.**
  1. Return early from `runArtAndMotion` on `placeholder` and show a friendly card (15 min).
  2. Per-call deadlines: chat and rubric 10 s, moderation 5 s, Gemini text 10 s, Gemini image about 25 s.
  3. One jittered retry for chat, rubric and moderation. Retry art at most once, and only on 5xx/429.
  4. Per-function `timeoutInterval` in the app.
  5. Map non-envelope 5xx to `.upstream` and 401 to `.unauthorized`.
  6. Keep a failed input in the text field for a one-tap resend.
- **Confidence.** Checked: by grep and by tracing the code. Failure rates are unknown.

<a id="imp-11"></a>
### IMP-11 · Overlapping page animations on one session, and no first-frame watchdog · MEDIUM · ~4 h
- **What.**
  - `SessionController` is a reentrant actor. A second `animate()` during page 1's ~1.6 s prepare (a fold, or a revision's `motionReady`) starts a second prepare on the same JS controller, and the waiters in `waiters.ts` resolve for either flow. A scratch repro against a fake Orbis that follows the schema failed page 1 with *"start: not ready"*.
  - There's no timeout between `start` and `firstFrame`. The page can sit on `.preparing` forever, and the guard at `LivePageController.swift:86` blocks a retry.
- **Fix.**
  1. Give each prepare a generation token: newest wins, older waiters reject as "superseded", and `firstFrame` carries the token.
  2. Add a first-frame watchdog of about 8–10 s after `generation_started`.
  3. Cut the per-page `conditions_ready` timeout to about 15 s.
- **Confidence.** Checked: the code, plus the repro against a fake. Behaviour against real Orbis is unverified. How often a fold lands in the prepare window is unmeasured.

<a id="imp-12"></a>
### IMP-12 · Session hygiene: warm-up time, a hard cap, resolution and audio · LOW · ~1.5 h · related R-08, R-30
- **What.**
  - Reactor's billing page says *"the meter runs for every minute the GPU is held for you, even if you are idle"* and advises against speculative pre-warming (docs.reactor.inc/resources/billing).
  - ROADMAP §9 still says T-60 (about $35 idle at the project's price), though 0.3a measured connect at 3.5 s.
  - The mint body (`reactor_client.ts:20-32`) doesn't set `constraints.max_session_duration_seconds`, a server-enforced cap on any leaked session.
  - The app never sends `set_resolution` or `set_audio_enabled`, so video arrives at 2560×1440 and 7–10 Mbit/s for 832×480 content, with an audio track the PRD says is off.
  - Reactor's billing page lists Orbis Stable's price as **"TBD"**, so every dollar figure in the PRD rests on the unsourced $0.582/min.
- **Fix.**
  1. Warm at about T-2 min.
  2. Mint with `max_session_duration_seconds` of about 1800.
  3. After connect, send `set_resolution('1080p')` and `set_audio_enabled(false)`. Both survive `reset`.
  4. Record clips from a page-sized canvas at about 1.5 Mbit/s.
  5. Confirm the price with Reactor.
  6. **Don't** disconnect between pages to save money: each reconnect spends a token session and adds on-stage risk.
- **Confidence.** Checked: the Reactor billing, sessions, authentication and schema docs, and grep. Bandwidth savings are estimates.

<a id="imp-13"></a>
### IMP-13 · Finishing the book: 17–45 s of dead air per page without a clip · HIGH · ~3 h · related R-05
- **What.**
  - `BookView.finish` (`:156-167`) awaits `completeClips()`, then `end()`, then the title, then cover art, all one after another.
  - `completeClips` (`StoryMaker.swift:267-285`) re-animates each page that has no clip, one at a time: about 1.6 + 4.8 + 10 s plus transfer, with up to 45 s per page.
  - On the Finish button, the single live web view shows other pages' video over the page on screen (`ArtPageView.swift:39-43`).
  - On close-to-finish, the web view is unmounted (`BookView.swift:57-59` swaps in `CoverView`), and whether WebKit keeps firing `requestVideoFrameCallback` for a detached view is unknown. The closed path has never run in automation: the scripted finish runs with the book open.
- **Fix.**
  1. **Save at once** with stills for pages missing a clip, and fill clips in the background, which IMP-04's server-side clips make possible.
  2. Generate the title and cover while the book is being made (once page 2 exists), not at close.
  3. Show video only when the live page id matches the page on screen.
  4. Show "Finishing · 2 of 4".
  5. Add a drill: make two pages, close with the slider, and time it.
- **Confidence.** Checked: the code. Timings are derived from 0.3a (n=1).

<a id="imp-14"></a>
### IMP-14 · Rate limits can block the demo, and the message tells the presenter to just retry · MEDIUM · ~1 h
- **What.**
  - Art is limited to **20/min** and **300/day** per user (`rate_limit.ts:12,20`), on a fixed UTC day that resets at 17:00 PDT.
  - Each page version costs up to 4 art calls: the page, then a plate and 1–2 cutouts fired eagerly after every stored still (`StoryMaker.swift:219`, `LayerMaker.swift:14-45`). Cancelled calls still count.
  - The anonymous user persists in the Keychain, so dev runs, end-to-end runs and rehearsals share one bucket. About 7–10 six-page books with revisions use up the daily cap.
  - Both limits return "Pop! is taking a quick breather — try again in a moment" (`Envelope.swift:24`). Failed layers are only logged, and the pop-up quietly becomes a flat card.
- **Fix.**
  1. Make the caps env-driven and raise the daily cap for demo week.
  2. Give plate and cutout their own bucket so they can never starve page art.
  3. Use a distinct message for the daily cap.
  4. Show today's art count in the debug overlay and in preflight.
  5. Make layers only once a page version has been stable for about 6 s, never for empty text.
- **Confidence.** Checked: the code and SQL. Per-book counts are derived, not measured.

<a id="imp-15"></a>
### IMP-15 · Run-book: add a preflight script, a golden-book backup and drills · MEDIUM · ~4 h (folds into Phase 9)
- **What.**
  - The golden book lives only in the simulator's app container, and R-21's fix (erasing the Duo) would wipe it along with the Keychain user.
  - There's no preflight check, no screen-recording fallback and no drill script.
  - The stats event doesn't report the ICE candidate type, so whether WebRTC went direct or through TURN over TCP is invisible.
  - Supabase Free projects pause after a week of inactivity, and the project's plan isn't recorded.
- **Fix.**
  1. `scripts/preflight.sh`, read-only, printing PASS/FAIL. It checks that: DeviceHub is running and the Duo is booted to its home screen; the app and golden book are present; each function returns its envelope (which also warms them); 0 Reactor sessions are open; today's art count; the Mac's default input device (not AirPods); download speed ≥ 15 Mbit/s; no colima or xcodebuild is running.
  2. `scripts/golden.sh backup|restore` to a git-ignored folder, plus a screen recording of a full good run as the last resort.
  3. Drills, each with its expected result: Wi-Fi off mid-page; a Reactor 429; an OpenAI 5xx; art rejected by moderation; art cap exhausted; close with two unclipped pages; a fresh install; UDP blocked with `pfctl`; network off → golden book.
- **Confidence.** Checked: `scripts/`, the docs and the Supabase pausing doc. The drills are proposals.

---

## Output quality

<a id="imp-16"></a>
### IMP-16 · Characters are cut off by the page crop, measured on the golden book · HIGH · ~2 h · related R-04
- **What.** Pictures are 16:9, and a portrait page (about 475×669 pt) shows about 40% of the width. CONTRACTS §1 says "important content central", but **no prompt says so** (grep of `art_style.ts`, `art_request.ts`, `story_prompt.ts`). Apple Vision foreground masks on the five committed golden-book stills show **74%, 90%, 78%, 47% and 77%** of subject pixels visible in the page crop. On `sample-fox-3`, half the frog and the fox's tail fall outside the page. The same crop hits the Orbis video and the pop-up plate.
- **Fix.**
  1. Add a composition clause in `buildArtPrompt` for kind `page` and `plate`: every character and the key action inside the middle 40% of the width, with only continuous background (sky, grass, trees) in the outer thirds.
  2. Regenerate the golden book, and keep the Vision check as a regression script.
  3. Now that the hinge works, the demo can run on the inner spread, where this crop applies in full. Settle D9 for that page shape.
- **Confidence.** Checked: measured independently twice on the host Mac. The clause's effect is untested, since it needs paid calls.

<a id="imp-17"></a>
### IMP-17 · The pop-up doesn't match the picture it replaces · HIGH · ~3 h
- **What.**
  - The plate and cutouts are generated from text alone (`LayerMaker.swift:16-26`). `referencePathsFor` returns `[]` for plate (`art_request.ts:39-44`), yet `PLATE_INSTRUCTION` says "identical to the page illustration", an image Gemini is never sent. So at 90° the audience sees a different scene.
  - Cutouts sit in fixed slots (centre, ±25% of the width; `PopUpView.swift:41-45`), whatever their position in the still.
  - "Page full. Fold to turn" shows before the next page has a still or layers (`BookView.swift:89-95`), so folding when told to shows "Painting…" or the flat card.
- **Fix.**
  1. Add a `sourcePath` (the page still) to the art request for plate and cutout, sent as an input image with edit-style instructions: "remove X and fill in behind", and "redraw only X exactly as it appears". 2.5 Flash Image supports editing too.
  2. Have the cutout call report the character's position so `PopUpView` places it where it was.
  3. Under P-04, show the fold cue only once the page behind has its still, and a "pop-up ready" cue once its layers land.
- **Confidence.** Checked: the code. The mismatch is inferred from the missing image input, not rendered.

<a id="imp-18"></a>
### IMP-18 · Character consistency rests on text alone · MEDIUM · ~3 h
- **What.**
  - No code ever requests art of kind `.character` or `.drawing`, and nothing sets `Character.referencePath`, so every page sends zero reference images, against S6.
  - `buildArtPrompt` labels **every** bible character "Characters appearing in this picture" on **every** page (`art_request.ts:80-84`), which tells the model to paint the whole cast whatever the text says. That also makes the IMP-16 crop worse.
  - The kid's-drawing feature (`1764ef0`) has no caller.
- **Fix.**
  1. List only characters named in the page text or art prompt (reuse `charactersOnPage`), under the heading "Character notes (draw only those this scene includes)".
  2. After IMP-06 makes ids stable, make one background `.character` reference sheet when a character first enters the bible.
  3. Mark the drawing feature "not in the demo".
- **Confidence.** Checked: by grep. The drift itself is expected, not observed.

<a id="imp-19"></a>
### IMP-19 · Cutout keying leaves magenta holes and fringes · MEDIUM · ~3 h
- **What.**
  - `BackgroundKey.swift:10-52` flood-fills only backdrop that touches the border, with hard 0/255 alpha, no despill and no crop.
  - On a synthetic test image it left 9,162 opaque magenta pixels (an enclosed arm loop) and a magenta fringe on every edge.
  - The cutout prompt asks for both "textured paper look" (`ART_STYLE`) and "no paper texture" (`art_request.ts:71-75`).
  - `ChromaKey.swift` (green) is dead code, and its comment contradicts CONTRACTS (magenta).
  - Vision background removal fails in the iOS 27.0 simulator ("Could not create inference context"), so ROADMAP §3's assumption holds.
- **Fix.**
  1. Remove *enclosed* components only when they are near the border's median colour, low in variance and above a minimum size: a hole test, not a hue test. A global magenta key would punch holes in pink and purple characters, which are common in kids' books.
  2. Add a soft alpha ramp and despill on the edge ring.
  3. Drop "textured paper" for the cutout kinds.
  4. Crop to the alpha bounding box.
  5. Delete `ChromaKey.swift`.
- **Confidence.** Checked: the committed code run on a synthetic image, and Vision run in the simulator. Real Gemini cutouts weren't tested.

<a id="imp-20"></a>
### IMP-20 · Smaller quality items · LOW · ~4 h total
- **The moment the still comes alive jumps.** The still sits at 1.02× zoom and +2% offset when not panning, and snaps from its pan position as the video fades in at 1.0× (`StillPanView.swift:17-22`, `ArtPageView.swift:34`). Make the resting state identity, ease the pan back over about 1 s when prepare starts, and keep one fade, not both the CSS and the SwiftUI one.
- **The pop-up may stutter.** `StillImageLoader` decodes a fresh `UIImage(contentsOfFile:)` inside view bodies, with no cache, on every pop-depth step: up to 4 full-size PNGs, measured at 11 ms p50 each on the host (`ArtPageView.swift:19,54-55`). Add an `NSCache` of pre-decoded images keyed by path, sized to the pane.
- **The cover risks lettering.** The cover prompt includes the quoted title (`BookView.swift:196`), which invites the model to draw letters despite "no text". Describe "leave the top third as plain sky" instead, and pre-generate the cover once page 2 exists.
- **Checks outside the app.** The App target has no tests, and `sim.sh` always builds Debug; `BackgroundKey` takes 251 ms in Debug versus 11 ms in Release. Add `scripts/check.sh`: `swift test`, `npm test`, typecheck, `npm run build`, then `xcodegen generate`, then `git diff --exit-code App/LiveScene/Web Pop.xcodeproj`.

---

## Premise and bigger choices

<a id="imp-21"></a>
### IMP-21 · Use pre-rendered image-to-video as the fallback, not the still-pan · MEDIUM · ~4 h prototype · question for Brian
- **What.** Pre-rendered image-to-video is now cheap and quick. fal's MiniMax H3 Max Turbo image-to-video costs $0.04/s at 768p, about $0.20 per 5 s clip (https://fal.ai/models/minimax/h3-max-turbo/image-to-video). fal quotes about 1.5 s of *inference*; wall-clock time with upload and queue is unmeasured. Its output **follows the input image's aspect ratio (9:16 to 21:9)**, so a portrait clip avoids the 60% crop entirely.
- **Recommendation.**
  - Don't replace Orbis: it's the pitch, and PIVOTS' red lines protect live generation.
  - Prototype it as P6's fallback (instead of the still-pan) for pages whose live session failed or was held. Store the clip next to the still, moderate 2–3 sampled frames, and play it with the existing `ClipPlayerView`.
  - **Question:** is Orbis a hackathon requirement? If it isn't, this could be the default, with Orbis as a "live" mode.
- **Confidence.** Checked: fal's model and pricing pages. Quality on watercolour stills and real wall-clock time are unmeasured.

### IMP-22 · Scope: there's no rehearsal evidence yet · LOW · question for Brian
There's no rehearsal log or latency table in `docs/`, and Phase 9 comes last by D8's "no deadline, build everything". That's Brian's decision, so this is a question, not a proposal. **If there is a demo date**, run the golden path once now to produce the missing latency table (IMP-03) and the first rehearsal before adding more features. A 90-second script to rehearse against: cover → open (page 1 pops) → tell two pages → a direction rebuilds the page behind → fold → hold 90° pop-up → close to save → reopen from the shelf with Wi-Fi off.

### Checked and kept as they are
- **The WKWebView + JS SDK bridge.** Keep it. Reactor now has a native Swift SDK (github.com/reactor-team/reactor-client-sdks, v1.1.0, 2026-09-15), so ROADMAP §3's "no Swift SDK" is out of date. But it has no XCFramework release yet, and building it needs Rust and libwebrtc. Worth another look later.
- **The vendor split.** Keep OpenAI for the story, moderation and speech, and Gemini for art. Moving to one provider shows no latency gain.

---

## Moot or changed after P-04

These were found against the code as it is, which still uses `append / new_page / revise_current`. P-04 reworks that code, so each item below is carried forward as a requirement for the rework rather than a fix to the current code.

| Finding | Status after P-04 | Carry forward |
|---|---|---|
| An `append` over the word limit makes a second model call and a second gate, then drops the words with a *safety* note (`story_turn.ts:113-126, 163`) | The `append` path goes away | Check the word limit locally **before** the paid safety gate, and never show the safety note for a length problem |
| Pictures reflect only the first sentence, because appends never re-illustrate (`PagePipeline.swift:168-175`) | Moot: pages are built whole along the path | — |
| Live-steer the running Orbis session on a direction with `setPrompt` (a ~4–6 s visible reaction) | **Conflicts with P-04**: the page on screen never changes | Not recommended |
| Words said after a break but before the fold overwrite the pending page (`StoryMaker.swift:177,184`) | The flow changes, but the routing bug is IMP-01 | Covered by IMP-01 |
| Every sentence cancels and restarts in-flight art | Now happens on the page behind when directions come quickly | Covered by IMP-02 |

## Claims that were checked and corrected

The skeptic pass corrected these, so they aren't in this doc as originally stated:
- Semantic voice detection with eagerness `high` *reduces* split sentences: **wrong way round**. `high` cuts sooner.
- `gpt-4o-transcribe` doesn't support realtime: **misread**. It is supported on the GA endpoint the app uses.
- Passing `req.signal` to Gemini stops billing for cancelled images: **doubtful**. Not issuing the superseded call (IMP-02's debounce) is the real saving.
- D9 option (c) (Dynamic portrait) is ruled out: **not shown**. The Stable schema's 16:9 rule says nothing about Dynamic.
- Leaked sessions could pile up to Reactor's 5-session limit: **unlikely**. Reactor ends a session 30 s after its connection drops. The IMP-12 cap still helps for a session held open by a forgotten screen.
- About 90% of Orbis spend is idle: **wrong framing**. The live page on screen is the product. The waste is paying for live generation where a looped recording would look the same (IMP-04).
- The fal benchmark's "1.6 s" is an end-to-end clip time: **no**. It's text-to-video inference only.

## Questions for Brian

1. **Is there a demo date?** It decides whether IMP-22 matters, and how much of the list below "Start here" to do.
2. **Is Orbis mandatory** (a sponsor or hackathon requirement)? It decides IMP-21.
3. **Is the demo on the inner spread** now that the hinge works? That makes D9 the portrait-page decision again (IMP-16).
4. **Can Reactor confirm Orbis Stable's price** (its docs say "TBD") and whether its recorder (`requestClip`) is enabled for Orbis (IMP-04)?

## How this was done

- **Reviewers.** Six reviewers, one per area (story latency; art and pop-up; Orbis; server and demo reliability; app and posture; premise and vendors). Then an independent skeptic per area tried to refute each finding against the code, the docs and vendor sources. None were refuted outright; most had their impact or fix corrected, and the corrected versions are what's written here. Findings from the premise area that the skeptic confirmed or weakened are included too.
- **What was run.**
  - All three suites on `5e0d4e5`: PopKit 157/157, `web/live-scene` 15/15 plus typecheck, edge functions 157/157 (Deno 2.9.6).
  - Scratch reproductions outside the repo: the overlapping-prepare failure against a fake Reactor SDK; the stale-copy and blank-page sequences with the real `BookReader.swift`; Vision crop measurements on the golden stills; `BackgroundKey` on a synthetic cutout; PNG versus JPEG size and decode time; Vision in the iOS 27.0 simulator.
- **What wasn't run.**
  - The app itself: this Mac has Xcode 27.0 and no iPhone Duo simulator.
  - Any paid API call (Reactor, Gemini, OpenAI).
  - Any latency beyond the Phase 0 probes, so every other number here is an estimate, labelled as one.
- **Ownership.** This file is new and owned by nobody yet. The builder and QA can fold items into REVIEW.md, and product questions can go to Pivots.
