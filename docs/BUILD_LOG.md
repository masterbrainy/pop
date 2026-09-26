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

Keys stay in `supabase/functions/.env`. The scripts read them into shell variables, pass them to `curl` through a header file, and print only HTTP statuses.

## 2026-09-25

- **Go.** Brian opened the build gate: build all phases without further check-ins.
- **Project skeleton.** XcodeGen (`project.yml`) + `xcodebuild`, app target `Pop` (iOS 27.1, Swift 6), local package `PopKit` for testable logic (Swift Testing). `Pop.xcodeproj` is generated; edit `project.yml` instead.
- **0.1 hinge and 0.2 spread probes** ran on the closed Duo; results are in ROADMAP §3. The hinge can only be moved by hand in DeviceHub, so posture logic is tested against a scripted hinge and an in-app debug slider.
- **Live-scene bridge.** `web/live-scene` bundles Reactor's JS SDK (3.0.2) into a page the app serves itself at `popscene://app/…` (`SceneSchemeHandler`), so the SDK can load its wasm and reach Reactor (whose API allows any origin). Swift drives it through `LiveSceneBridge` (`window.popScene.connect / prepare / start / setPrompt / reset / disconnect`); events come back as PopKit's `SceneEvent`.
