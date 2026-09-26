# Pop! build log

The builder's running log: what works, how to run it, and what's next. Newest first. Measured platform facts go in [ROADMAP §3](ROADMAP.md#3-platform-facts) and decisions in [§10](ROADMAP.md#10-decision-log); this file points to them.

## How to run things

Keep **DeviceHub** open (`Xcode-beta.app/Contents/Applications/DeviceHub.app`); a Duo booted without it stays on the Apple logo.

| What | Command |
|---|---|
| Build, install and launch on the iPhone Duo simulator | `scripts/sim.sh run` |
| Open a Phase 0 probe directly | `scripts/sim.sh run -probe hinge` (or `spread`, `orbis`) |
| Screenshot both screens into `build/shots/` | `scripts/sim.sh shot <name>` |
| Animate one picture with Orbis (mints a 15-minute token from `.env`; about $0.30 per 30 s of video) | `scripts/probe-orbis.sh <still.png> "<motion prompt>" [seconds]` |
| See or kill open Reactor sessions (run after any Orbis work) | `scripts/reactor-sessions.sh list` / `kill` |
| One Gemini picture (dev only) | `scripts/gemini-image.sh "<prompt>" out.png [16:9]` |
| Logic tests | `cd PopKit && swift test` |
| Live-scene bridge tests and type check | `cd web/live-scene && npm test && npm run typecheck` |
| Rebuild the live-scene page after changing `web/live-scene/src` | `cd web/live-scene && npm run build` (writes `App/LiveScene/Web/`) |
| Scripted end-to-end story (live server + Orbis); log in the app's `Documents/story.log` | `xcrun simctl launch booted com.masterbrainy.pop -screen create -debugHinge YES -storyTurns "a fox finds a leaf\|wait\|fold\|you continue\|wait\|finish"` |
| Open the newest saved book (replays clips, no generation) | `xcrun simctl launch booted com.masterbrainy.pop -screen latest` (add `-debugHinge YES -hingeAngle 92` to hold the pop-up) |
| Log real hinge readings to `Documents/hinge.log` | add `-logHinge YES` |
| Story eval set (42 sessions against the deployed `story-turn`) | `deno run --allow-net --allow-read --allow-env --allow-write scripts/eval/run.ts` |
| Server tests | `cd supabase/functions && deno test --allow-env` |

Keys stay in `supabase/functions/.env`. The scripts read them into shell variables, pass them to `curl` through a header file, and print only HTTP statuses.

## 2026-09-26

- **Evening: the book works end to end in the Duo simulator.** Typed turns become text, then a picture, then live Orbis video, then a recorded 10 s clip. Folding turns the page, "You continue" adds to the story, and finishing makes a title and a painted cover and saves the book. `-screen latest` replays it from disk with no network calls.
- **Inner spread verified** with the real DeviceHub hinge (text left, picture right, 2853×2007 px). A slow fold turns the page. Opening can leave the inner display asleep until it's clicked once. Details in ROADMAP §3.
- **Pop-up layers:** the plate plus up to two cutouts, drawn on a flat magenta backdrop and keyed on the device by `BackgroundKey` (edge flood fill from the border's median colour).
- **Characters stay the same:** after a character's first picture, a 1:1 reference sheet is made from it and attached to later pages, cutouts and the cover.
- **Safety and cost:**
  - A frame tripwire moderates a sampled frame at 3 s, then every 15 s; a flagged frame holds the page on its still.
  - KILL, backgrounding and late connects all end the Orbis session (R-30). Verified: 0 open sessions after locking mid-animation.
  - The triple-tap debug panel shows status, credits, frame checks, p50/p90 latencies and KILL.
- **Story quality:**
  - A full page now flows onto the next page instead of being refused, and pages that retell earlier pages are trimmed.
  - Eval: 41/42 pass, 0/28 safety misses, false blocks down from 21% to 7%.
  - Turns queue, so a second input can't drop the first (R-31).
- **Measured p50:** story-turn about 2.7–5 s, art about 7 s, motion-prompt about 6.5 s, character reference about 8.5 s, cover about 8.7 s.
- **Tests:** PopKit 166, Deno 165, web 15, plus eval checks 18. All pass.

- **Computer control on.** Brian granted full-screen control; DeviceHub's Duo window is driven directly. Restarting DeviceHub shuts the Duo down (it hosts the device); boot it from DeviceHub's Start button, not `simctl`.
- **The Mac is overloaded** (load average 60–400 on 8 cores, mostly the simulator runtime's disk image and builds), so `simctl` calls, screenshots and page loads can take 10–30× longer. Scripts wrap slow calls in `perl -e 'alarm N; exec @ARGV'`.
- **0.3a Orbis go/no-go: GO.** WebRTC video plays in the app's WKWebView on the Duo simulator. Numbers in ROADMAP §3. Orbis drifts toward photoreal unless the prompt restates the art style, so `motion-prompt`'s scene starts with the style words.
- **Phase 1 UI** committed (f33f3c9): bookshelf, spread, curl, cover, debug hinge. **Clip recording** added to the bridge: `startClip / stopClip / cancelClip` record the video with MediaRecorder and stream it to Swift (`popClip` → `ClipAssembler` → `Documents/clips/`).
- **Tracks in parallel:** a backend agent finishes, tests and deploys all server functions; a PopKit agent builds the logic modules test-first (server client, story engine, page pipeline, session controller, book store, chroma key, read-along ranges); the builder does the app UI.

## 2026-09-25

- **Go.** Brian opened the build gate: build all phases without further check-ins.
- **Project skeleton.** XcodeGen (`project.yml`) + `xcodebuild`, app target `Pop` (iOS 27.1, Swift 6), local package `PopKit` for testable logic (Swift Testing). `Pop.xcodeproj` is generated; edit `project.yml` instead.
- **0.1 hinge and 0.2 spread probes** ran on the closed Duo; results are in ROADMAP §3. The hinge can only be moved by hand in DeviceHub, so posture logic is tested against a scripted hinge and an in-app debug slider.
- **Live-scene bridge.** `web/live-scene` bundles Reactor's JS SDK (3.0.2) into a page the app serves itself at `popscene://app/…` (`SceneSchemeHandler`), so the SDK can load its wasm and reach Reactor (whose API allows any origin). Swift drives it through `LiveSceneBridge` (`window.popScene.connect / prepare / start / setPrompt / reset / disconnect`); events come back as PopKit's `SceneEvent`.
