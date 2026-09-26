# Pop! — Improvement audit

*An outside review of `main` @ `5e0d4e5`, rebased on `fd71c50` (2026-09-26, after P-04, the R-30 and R-31 fixes, QA's R-35–R-39, the working hinge and the golden-book run-book). Read-only: no code was changed. Priorities, in order: **latency**, **demo reliability**, **output quality**; then cost and stack logistics. Nothing was off the table, including the premise. Findings already in [REVIEW.md](REVIEW.md) (R-01 to R-39) aren't repeated unless something new was found; related R-IDs are named.*

**How to read this.** Each item says what's wrong, where (file:line), the fix, a rough effort, and **what was checked versus estimated**. Latency numbers other than the Phase 0 probes (Gemini 5.0 s; Orbis prepare 1.6 s plus first frame 4.8 s; one story-model call of 2.3 s from the timing fixture in `c20e90f`) are estimates, because no end-to-end latency table exists yet (IMP-03). Everything was reviewed against the post-P-04 PRD. Where the code hasn't caught up with P-04, the item says whether it still applies.

---

## Start here: six things, in order

| # | Item | Why now | Effort |
|---|---|---|---|
| 1 | [IMP-23](#imp-23) Re-saving a reopened book deletes its pictures | Data loss that already happens when a parent reopens a draft and closes it; every collections feature would re-save more often | ~1 h |
| 2 | [IMP-01](#imp-01) Results are applied by page index onto an old copy of the book | Clips and pop-up layers get silently wiped; folding mid-turn strands the parent on a blank page. Both paths are P-04's core flow | ~6 h |
| 3 | [IMP-02](#imp-02) The R-31 fix makes the next input wait for art | A direction spoken during a turn waits ~10–15 s before its text even starts | ~3 h |
| 4 | [IMP-03](#imp-03) Measure before optimising | No PRD §5 latency target can pass or fail on evidence today; the order of everything below depends on it | ~3 h |
| 5 | [IMP-04](#imp-04) Animate the page behind before the fold (record, then loop) | The only way to meet "fold → animation ≤ 5 s" with one session, and it is exactly P-04's "gentle, repeating motion" | ~12–16 h |
| 6 | [IMP-05](#imp-05) Make the fold reliable on stage | Hinge readings are sparse, so a quick fold can miss the turn; script the folds | ~2–3 h |

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
  - (Related R-38.) The frame tripwire checks at 3 s and then every 15 s (`FrameTripwire.swift:18-19`), but a clip is 10 s long, so most of every saved clip is never moderated. And `hold()` never clears a clip that's already attached. Check 3–5 frames sampled from the finished clip before attaching it.
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

<a id="imp-23"></a>
### IMP-23 · Re-saving a reopened book deletes its pictures · HIGH · ~1 h
- **What.**
  - When a book is loaded, `AppModel.resolvingPaths` (`App/Shell/AppModel.swift:70-86`) points every page's still, layers, clip and cover at the store's own files in `…/<bookId>/media/`.
  - On save, `FileBookStore.copyMedia` (`PopKit/Sources/PopKit/Store/BookStore.swift:120-131`) deletes the destination and then copies the source over it. For a reopened book, the source *is* the destination: the file is deleted and then `copyItem` fails.
  - `BookView.close()` (`:169-173`) re-saves any reopened draft that has text, so this already happens when a parent reopens a draft and closes it. `AppModel.save` reports only a text error.
- **Fix.**
  1. Skip the copy when the source and destination are the same file, and add a PopKit regression test: save, load, save again, and all media still exists.
  2. Keep shelf metadata (favourite, last opened, series) in a small separate file, so marking a favourite never re-copies about 48 MB of media (IMP-26).
- **Confidence.** Checked: by reading the code (both paths). A scratch copy of PopKit reproduced it: *"RESAVE threw=true fileStillExists=false"* (NSCocoaError 260).

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
### IMP-12 · Session hygiene: warm-up time, a hard cap, resolution and audio · LOW · ~1.5 h · related R-08
- **What.**
  - Reactor's billing page says *"the meter runs for every minute the GPU is held for you, even if you are idle"* and advises against speculative pre-warming (docs.reactor.inc/resources/billing).
  - The run-book (`5f7eab1`) now warms Orbis only when the demo's New book opens, which is right: 0.3a measured connect at 3.5 s. Keep it that way; don't pre-warm.
  - The mint body (`reactor_client.ts:20-32`) doesn't set `constraints.max_session_duration_seconds`, a server-enforced cap on any leaked session.
  - The app never sends `set_resolution` or `set_audio_enabled`, so video arrives at 2560×1440 and 7–10 Mbit/s for 832×480 content, with an audio track the PRD says is off.
  - Reactor's billing page lists Orbis Stable's price as **"TBD"**, so every dollar figure in the PRD rests on the unsourced $0.582/min.
- **Fix.**
  1. Keep warm-up at New book (no earlier).
  2. Mint with `max_session_duration_seconds` of about 1800.
  3. After connect, send `set_resolution('1080p')` and `set_audio_enabled(false)`. Both survive `reset`.
  4. Record clips from a page-sized canvas at about 1.5 Mbit/s.
  5. Confirm the price with Reactor. Its billing page says billing is **per session-minute** from `ready`, and that connecting is free, so PRD §9's "billed per second" needs correcting.
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
### IMP-15 · Run-book: automate the checks and add drills · MEDIUM · ~3 h (folds into Phase 9) · updated for `5f7eab1`
- **What.**
  - `5f7eab1` added `scripts/golden-book.sh` (backup and restore) and a concrete run-book with a failure table. That covers the golden-book risk and most manual checks. What's left is automating the checks and rehearsing failures.
  - There's still no scripted preflight check, no screen-recording fallback and no drill script.
  - The stats event doesn't report the ICE candidate type, so whether WebRTC went direct or through TURN over TCP is invisible.
  - Supabase Free projects pause after a week of inactivity, and the project's plan isn't recorded.
- **Fix.**
  1. `scripts/preflight.sh`, read-only, printing PASS/FAIL. It checks that: DeviceHub is running and the Duo is booted to its home screen; the app and golden book are present; each function returns its envelope (which also warms them); 0 Reactor sessions are open; today's art count; the Mac's default input device (not AirPods); download speed ≥ 15 Mbit/s; no colima or xcodebuild is running.
  2. Keep a screen recording of a full good run as the last resort.
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
### IMP-18 · Character consistency: every page lists the whole cast, and references can be lost · MEDIUM · ~2 h · updated for `f1aedd3`
- **What.**
  - Since `f1aedd3`, a 1:1 reference sheet is drawn from a character's first picture and attached to later pages, cutouts and the cover (`CharacterReferences.swift`, `StoryMaker.makeReferences`). That fixes the biggest gap.
  - Two problems remain.
    - `buildArtPrompt` still labels **every** bible character "Characters appearing in this picture" on **every** page and cover (`art_request.ts:79-83`). That tells the model to paint the whole cast whatever the text says, and it makes the IMP-16 crop worse.
    - References are carried by the character id the *model* writes (`carryingReferences`, `CharacterReferences.swift:31`), and ids are never shown to the model (IMP-06). A renamed id silently drops the reference.
- **Fix.**
  1. Filter the list to characters named in the page text or art prompt (reuse `charactersOnPage`), under the heading "Character notes (draw only those this scene includes)".
  2. Make ids server-owned and immutable (IMP-06's `bibleDelta`), or add a stable `libraryId` that the app assigns (IMP-26).
- **Confidence.** Checked: the code at `eba14be`. Drift is expected, not observed.

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

## Part 2 · Guided story making, collections and a second Orbis session (proposed pivots)

*Added 2026-09-26 at the teammate's request. They asked for four things:*
1. *A guided setup that gathers what a good story needs.*
2. *Better questions during the story instead of everything being free-form.*
3. *Collections so the family can revisit stories.*
4. *A second Orbis session so the next page can be animated while the current one plays.*

*Five researchers (kids' storytelling evidence, prior apps, code fit, Orbis, collections), one designer and one critic worked on these. The critic's corrections are folded in.*

*All four change PRD scope, so they're **proposed pivots for Brian**. The Pivots session assigns the P-numbers.*

**The idea that ties them together.** P-04's story path gets a fixed shape: 3 beats for ages 3–4 (beginning, middle, end) and 5 beats for 5–8 (setup, problem, tries, turning point, ending). This is Toontastic's structure (https://www.commonsensemedia.org/app-reviews/toontastic-3d).
- The guided setup fills in the beats.
- Each page asks one question that fits its beat.
- The saved path and cast let a shelf group and continue stories.
- The time a parent and kid spend answering is when the next page gets built and animated.

Beats are labels on the pages of the path, not a new structure, so PRD S14 still stands.

**Rules for all four.**
- The parent leads, and whoever holds the phone can answer. The flow is the same when a parent makes a book alone.
- Answers use voice or picture tiles, so no reading is needed.
- Tiles use SF Symbols and bundled art. There's never an image call for a tile.
- Every generated question and choice passes the safety gate.
- No dark patterns: no pleading characters, no timers, no stickers, streaks or book counts, no autoplay into the next book. 80% of apps used by 3–5 year olds have manipulative design (Radesky et al. 2022, https://faculty.washington.edu/alexisr/childrenManipulativeDesign.pdf).

<a id="imp-24"></a>
### IMP-24 · Guided setup: four picture cards instead of three text boxes · proposed pivot · ~8–10 h
- **Today.** Three free-text fields: interests, a real moment, and "teach" (`App/Create/BriefSheet.swift:23-63`).
- **Proposal.** Four cards that anyone can answer by tapping or speaking, with "Surprise me" on each and "Just start" always available. Cards are read aloud with the on-device voice when the child is present (a toggle, off when a parent makes the book alone):
  1. **Who's the hero?** The child · a favourite from their interests · a saved character (IMP-26) · Surprise me.
  2. **Where?** 2 tiles for Listeners (3–4), 3 for older kids, chosen from interests with a small keyword-to-tile map.
  3. **What goes wrong?** Picture tiles for Listeners and Early readers; voice for Readers.
  4. **How should it feel?** Silly · cosy · brave (two faces for Listeners).

  Optionally, a first chip for "what's it for": fun · bedtime · a real moment… · teach something…. The last two open today's text fields, which stay optional.
- **Why this shape.**
  - Amazon's *Create with Alexa* used four spoken multiple-choice questions and counts pre-approved choices as one of its safety layers (https://www.amazon.science/blog/the-science-behind-alexas-new-interactive-story-creation-experience).
  - Children under about 3 tend to answer "yes" to any yes/no question (Fritzley & Lee 2003), so use either/or questions.
  - Working memory holds about 2–3 items around age 5 (Cowan 2016). So: 2 options for Listeners, 3 plus "something else" for older kids.
- **How it works.**
  - `StoryBrief` (CONTRACTS §1, `Models.swift:20-34`) gains `hero`, `place`, `problem`, `mood` and an optional `purpose`. Mirror them in the server's brief schema and `story_prompt.ts`.
  - P-04's new `plan` call replaces today's first turn, so the setup adds no model calls.
- **Latency.**
  - Fire `plan` as soon as the last card is answered, speculatively after card 3.
  - Start page 1's art the moment its art prompt comes back, and connect Orbis then too.
  - Don't connect when the setup opens. Reactor bills per session-minute from `ready` including idle time, and connecting is free (https://docs.reactor.inc/resources/billing). Connect takes about 3.5 s (probe 0.3a), which fits inside `plan`.
  - Honest timeline from the last card: plan (≥ 2.3 s) + gate (~1 s) + art (5.0 s) + Orbis prepare (1.6 s) + first frame (4.8 s) ≈ 14–15 s to a moving page 1. Page 1's **text** meets PRD §5's ≤ 5 s; its motion comes later, with the still showing first.
- **Before any typed text is used.** Typed brief text reaches the model unmoderated today (R-37). Add input moderation first.
- **Exit test.** On 5 real runs (paid, needs Brian's OK): setup to "Go" in ≤ 45 s with no typing, page 1 text ≤ 5 s after the last card, and every plan ends on an `ending` beat.

<a id="imp-25"></a>
### IMP-25 · One question per page, said aloud by the parent · proposed pivot · ~8–10 h · depends on IMP-02
- **Evidence.** Dialogic reading means the adult asks and the child answers. Its steps are PEER (prompt, evaluate, expand, repeat), with five prompt types, CROWD (completion, recall, open-ended, wh-, distancing).
  - The What Works Clearinghouse found it improves oral language by about 19 percentile points on average (https://ies.ed.gov/ncee/wwc/Docs/InterventionReports/WWC_Dialogic_Reading_020807.pdf).
  - A meta-analysis found d = .42 overall, and d = .59 on the words children say (Mol et al. 2008, https://eric.ed.gov/?id=EJ787378).
  - Two limits shape the design:
    - Enhanced e-books cut parent–child story talk, and parents talked about the device instead (Munzer, Radesky et al. 2019, https://pubmed.ncbi.nlm.nih.gov/30910918/). So the **parent** says the question aloud; the child's page never flashes or asks for a tap.
    - AI choice scaffolds raised weak storytellers but capped strong ones (https://arxiv.org/abs/2606.27067). So there's always a "something else / say it" option, most prominent for Readers.
- **What they see.** A strip under the text page that replaces the input bar while a question shows. It has:
  - one line to read aloud, for example *"Uh-oh, did Rex lose his ball or his hat?"*;
  - 2 tiles (Listener) or 3 plus "something else" (older);
  - Skip.

  A parent tip ("praise it, then ask why") shows only below the Reader level, where the child won't read it. Tapping a tile is a kid's-turn input, and the mic and typing still work.
- **Question mix.**
  - Listener: about 2 choice questions per book, with talk-only prompts ("Can you roar like Rex?") elsewhere.
  - Early reader: one per page, mostly choices.
  - Reader: open "what's the plan?" questions, with choices as a floor.
  - Distancing prompts ("Have you ever lost something?") are talk-only and never sent anywhere.
- **How it works.**
  - The question for a page is written by the same call that writes that page. Add a `question` field to `story_schema.ts`, nullable but required so OpenAI's strict mode accepts it: `{ask, kind: choice|open|talkOnly, choices: [{label, symbol, direction}]}`. `symbol` comes from an allow-list of about 40 SF Symbols.
  - Gate the question **separately and in parallel**. `runSafetyGate` is all-or-nothing (`safety.ts:33-69`), so one flagged choice must drop only the question, not the page.
  - Re-moderate a choice's text when it's tapped, because the app can send any text as a "choice".
  - Pass the chosen direction, or the default one, **explicitly** into the build of the next page. Hide the question after any re-plan that makes it stale.
  - Add `input.kind: "choice"` (`storyInputSchema`, `API.swift`).
  - `TurnQueue` must never merge a kid's words into a parent's input (R-37).
- **Latency.** No extra calls; about 150 more output tokens per page.
  - A choice that matches the default path costs nothing. A different choice rebuilds the page behind on P-04's re-plan path: about 2.3 s of text + the gate + 5 s of art, inside the 15 s budget and hidden by the talk that follows the answer.
  - This needs IMP-02 first. Today a tap made while art is running waits for art plus the motion prompt before its text even starts.
  - Pre-building art for every choice would triple Gemini calls and hit the 20/min art limit (IMP-14), so don't.
- **Scope.** This takes over PRD C3, the "reading together" strip, which is P2 on the cut list. Promoting it is Brian's call.
- **Exit test.** On the 30-session eval set: 0 K1 misses on questions and choices. A choice produces a rebuilt page behind at p50 ≤ 15 s (IMP-03 spans). A scripted Listener book shows at most one question per page and exactly 2 tiles.

<a id="imp-26"></a>
### IMP-26 · Collections: a shelf to revisit, series, and "another adventure" · proposed pivot · ~10–12 h for the demo
- **Today.**
  - The shelf is a flat grid (`BookshelfView.swift:44-56`), and books are saved only on the device (`FileBookStore`).
  - Reopening and closing a draft deletes its pictures (IMP-23).
  - One corrupt `book.json` makes `loadAll` throw, so only the sample book shows.
  - `page.motion` is never saved (`with(motion:)` has no callers), so a reopened draft's pages without clips can't animate.
  - `AppModel.delete` swallows errors, and every media file is stored twice on the device.
- **Demo subset.**
  1. **Make revisiting reliable** (~4 h): fix IMP-23, skip a corrupt book instead of failing, save the assembled motion prompt with the page, and make delete remove media and report errors.
  2. **Series and sequels** (~5 h):
     - `Book` gains an optional `seriesId`.
     - The shelf groups covers into rows by series ("Rex's adventures"), plus *New*. Covers are at least 180×240 pt, and tapping one speaks its title.
     - **"Another adventure with Rex"** lives in the **parent's** cover menu, not on the last page, so the child isn't nudged into the next book. It opens the guided setup with the hero pre-selected and seeds the new bible with the saved characters and their reference sheets (which exist since `f1aedd3`), plus `"Previously: …"` as the first direction. `story-turn` already accepts a bible, so no server change is needed.
     - Give characters a stable `libraryId` assigned by the app, because references are matched by model-chosen ids today (IMP-18).
  3. **Keep shelf metadata** (favourite, last opened) in a small separate file, not in `book.json`, so a heart tap never re-copies media.
- **Later.**
  - Supabase sync of book rows and clips (the tables and the private `pop-books` bucket exist), only while no book is being made.
  - A `.popbook` export and import behind the parental gate. It also protects the golden book from a simulator erase (R-21).
  - Saving stills as JPEG: about 48 MB per book drops to about 21 MB (estimate).
  - Anonymous sign-in means a lost Keychain entry makes cloud copies unreachable. Account linking and several kids' shelves are out of PRD §10 scope.
- **Privacy.** First names only. Keep cleaned page text only, with no audio and no transcripts. Add a gated "Forget this character".
- **Exit test.** A PopKit test that saves, loads and saves again keeps all media. A corrupt `book.json` beside 3 good books still shows 3 covers. Pages with clips replay with the network off; pages without one re-animate once Reactor is back. "Another adventure" produces a page-1 art request carrying at least one reference from the earlier book, and both books sit in one series row.

<a id="imp-27"></a>
### IMP-27 · A second Orbis session: not needed for the demo; build it only if the logs say so · proposed pivot · 0 h now, +8–12 h if triggered
- **Checked fact.** A second session doesn't need a second API key. Reactor allows **5 concurrent sessions per account**, pooled across all keys, with a burst of 3 creations and then about one every 6 s. A token's `max_sessions` defaults to 5, up to 500 (https://docs.reactor.inc/resources/rate-limits).
- **What actually limits Pop! to one session today:**
  - the web page hosts one Reactor client (`scene.ts:57`);
  - `SessionController` holds one page;
  - tokens are minted with `max_sessions: 2`, which counts every session a token ever opens, so a reconnect uses one up;
  - minting a token first ends the user's other sessions (`reactor-token/index.ts:70-72`), so a second mint would kill the first session;
  - the server returns `expiresAt` in milliseconds and the app reads seconds (`index.ts:74` against `SessionController.swift:105`).
- **Why one session is enough first.** P-04 wants each page's animation to be "a gentle, repeating motion", which is a loop.
  - Record the live page's clip server-side (`requestClip`, IMP-04) and loop it on screen. The single session is then free to animate the page behind and record it.
  - At the fold, if the session is **already streaming** the page behind, show that live stream at once. It's the right page, and recording carries on.
  - So the fold shows motion immediately whenever the page behind's still was ready about 6.4 s before the fold, or its clip is already recorded. That's most folds in a paced demo.
- **When a second session pays off.** Only when the page behind becomes ready while the single session is **busy** recording the current page. Log that per fold. If it's common in rehearsals, build a two-slot relay:
  - one web view with two Reactor clients, each with its own video element, and a `slot` argument on `window.popScene`;
  - two `SessionController`s that swap roles at each fold;
  - both streams at `set_resolution('1080p')`, since two 1440p decodes on a loaded Mac will drop frames.

  Cost roughly doubles while both run (per session-minute, idle included). At the project's unconfirmed $0.582/min, that's about $2.91 for a 5-minute book with one session and about $5.82 with two.
- **Needed either way.** Mint with `max_sessions` ≥ 4 and `max_session_duration_seconds` ≈ 1800; stop the mint ending sibling sessions; fix the ms/s unit bug.
- **Also needed.** Decide how clips loop (crossfade or ping-pong; R-05(4)): `AVPlayerLooper` jumps at the seam, and a looping page makes that seam visible.
- **Paid probe first** (~10 Orbis-minutes, about $6, needs Brian's OK):
  - Is `requestClip` enabled for Orbis, and what are its ready delay and resolution?
  - Warm `reset → first frame` over at least 10 runs (settles R-36).
  - Does `set_resolution` survive `reset`?
- **Exit test.** In a scripted 5-page book: fold to first moving frame p50 ≤ 0.3 s on folds made with the page behind ready. Every saved clip's (id, version) matches its page. The "busy when ready" share is logged on each of 3 runs.

### Build order for Part 2

| Phase | Work | Exit test |
|---|---|---|
| A | P-04's `story-turn` rework (`plan`/`replan`, outline-only path, bible delta) + IMP-01, IMP-02, IMP-03, IMP-23 + R-37 input moderation | Every plan ends on `ending`; a re-plan never changes the page on screen; a clip landing mid-turn survives; save → load → save keeps media |
| B | IMP-24 guided setup | ≤ 45 s to "Go" with no typing; page 1 text ≤ 5 s after the last card, over 5 real runs |
| C | IMP-25 questions | 0 K1 misses on questions and choices; choice → page behind rebuilt p50 ≤ 15 s |
| D | IMP-26 demo subset | Replay-exact after reopening; a series row after "Another adventure" |
| E | IMP-04 loop + IMP-27 single-session fixes, after the paid probe | Fold → motion p50 ≤ 0.3 s when the page behind is ready; "busy when ready" share logged |
| F | 5 rehearsals; decide the second session from the log | 5 clean runs; the decision written in PIVOTS |

About 30–40 h of new work on top of P-04's rework. Every hour figure is an estimate.

**90-second demo script** (with at least 20 s between each choice and the next fold):

| Time | What happens |
|---|---|
| 0–12 s | Four cards: Rex · the pond · "lost his ball" · silly. Go. |
| 12–27 s | Page 1 text is up; the parent reads it while the picture paints, then comes alive. |
| 27–35 s | The parent asks from the strip: *"Should Rex jump in or ask the bird?"* The kid taps *the bird*. The parent: "great idea, why the bird?" |
| 35–55 s | Talk; the strip shows "painting… ready". |
| 55–65 s | Fold: page 2 is already moving. Hold at 90° and the bird pops out of the spine. |
| 65–75 s | Close: the cover with its title. On the shelf it sits in *Rex's adventures* next to last week's book. |
| 75–90 s | Tap last week's cover with Wi-Fi off: it replays exactly. |


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
5. **Accept Part 2 as pivots?** Guided setup (IMP-24), one question per page (IMP-25, which promotes PRD C3 from the cut list), collections (IMP-26), and the one-session plan with a logged trigger for a second session (IMP-27).
6. **OK to spend about $6 on the Orbis probe** in IMP-27, and a few dollars on 5 real setup runs (IMP-24)?

## How this was done

- **Reviewers.** Six reviewers, one per area (story latency; art and pop-up; Orbis; server and demo reliability; app and posture; premise and vendors). Then an independent skeptic per area tried to refute each finding against the code, the docs and vendor sources. None were refuted outright; most had their impact or fix corrected, and the corrected versions are what's written here. Findings from the premise area that the skeptic confirmed or weakened are included too.
- **What was run.**
  - All three suites on `5e0d4e5`: PopKit 157/157, `web/live-scene` 15/15 plus typecheck, edge functions 157/157 (Deno 2.9.6).
  - Scratch reproductions outside the repo: the overlapping-prepare failure against a fake Reactor SDK; the stale-copy and blank-page sequences with the real `BookReader.swift`; Vision crop measurements on the golden stills; `BackgroundKey` on a synthetic cutout; PNG versus JPEG size and decode time; Vision in the iOS 27.0 simulator.
- **What wasn't run.**
  - The app itself: this Mac has Xcode 27.0 and no iPhone Duo simulator.
  - Any paid API call (Reactor, Gemini, OpenAI).
  - Any latency beyond the Phase 0 probes, so every other number here is an estimate, labelled as one.
- **Part 2.** Five researchers (Opus), one designer (Fable) and one critic (Opus). The critic re-checked file:line claims, found IMP-23 (reproduced in a scratch copy) and the stale reference claim in IMP-18, and corrected the latency plan, the demo timing and the second-session trigger. All 7 returned.
- **Ownership.** This file is new and owned by nobody yet. The builder and QA can fold items into REVIEW.md, and product questions can go to Pivots.
