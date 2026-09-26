# Pop! — Tech Notes

*A dated log of technical facts and decisions, each with its evidence. Owner: **Pop! · Pitch & Tech Log**. Sources so far: [PRD.md](PRD.md), [ROADMAP.md](ROADMAP.md), and the iOS 27.1 simulator SDK.*

## How this log works

- **Append-only.** New entries go at the bottom with the next `TN-` number. Never rewrite an old entry. If a fact changes, add a new entry that says "Supersedes TN-0xx". The only edit allowed on an old entry is adding "→ superseded by TN-0yy" to its title.
- **Every entry has evidence**: a file and line, a command and its output, a measurement, or a vendor doc.
- **Confidence tags:**
  - **Verified**: we checked it ourselves (SDK file, command output, HTTP status, measurement).
  - **Vendor docs**: the vendor says so and we haven't reproduced it yet.
  - **Reported**: a third party says so and we haven't checked it.
  - **Inferred**: our reading of names or signatures, to be confirmed by a probe.
  - **Decision**: a choice we made, with its reasoning and status (proposed, accepted or resolved).
- **Never write** key values, the Supabase project ref or URL, or personal data.
- Numbers we haven't measured say **TBD (measured in Phase N)**.

Entry template:

```
### TN-000 · YYYY-MM-DD · Title
**Fact:** … (or **Decision:** …)
**Evidence:** …
**Confidence:** Verified | Vendor docs | Reported | Inferred | Decision (proposed / accepted / resolved)
**So what for Pop!:** …
```

## Waiting on measurement

This index is not part of the append-only log. Update it freely, and link each answer to the entry that records it.

| Open question | Answered by | Entry |
|---|---|---|
| Does the simulator deliver a continuous hinge angle? How often does it update? | Phase 0.1 hinge probe | TBD |
| How does the simulator show the closed posture and the outer (cover) screen? | Phase 0.1 | TBD |
| Page size and aspect ratio; what `.division` and `.occlusion` actually mark | Phase 0.2 spread probe | TBD |
| Orbis warm-up time, `reset` to first frame, drift after 30 s and 60 s, Stable vs Dynamic, clip recording in `WKWebView` | Phase 0.3 Orbis probe | TBD |
| Does Orbis bill from connection or from generation? | Phase 0.3, plus a question to Reactor | TBD |
| How to record each page's clip (in-page recording or native capture of the web view), and how long each clip is (D4) | Phase 0.3, then Gate G0 | TBD |
| How long it takes a parent to make a 5-page lesson book | Phase 2 exit | TBD |
| Gemini p50 latency, character consistency, how well cutouts key out | Phase 0.4 | TBD |
| Realtime end-of-speech detection and latency; does Apple on-device speech work in the simulator? | Phase 0.5 | TBD |
| p50 latency per pipeline stage | Phase 2 exit | TBD |
| Cost per finished book, all vendors | Phase 2 (partial), Phase 5 (full) | TBD |
| Pop-up layers start rising ≤ 300 ms after the pop angle is reached | Phase 4 | TBD |

---

## Log

### TN-001 · 2026-09-25 · Toolchain: Xcode 27.1 beta and the iPhone Duo simulator
**Fact:** Xcode 27.1 beta, build 27A9269, is installed and selected. The iOS simulator SDK is 27.1. The **iPhone Duo** simulator device boots. The old Xcode 27.0 and every iOS 27.0 simulator image were removed.
**Evidence:** `xcodebuild -version` prints "Xcode 27.1 / Build version 27A9269", and `xcrun --sdk iphonesimulator --show-sdk-version` prints `27.1` (re-run by this session on 2026-09-25). Duo boot and cleanup: ROADMAP §1 (Day 0).
**Confidence:** Verified.
**So what for Pop!:** Everything is built and demoed in the simulator. Beta Xcode builds can't be submitted to the App Store.

### TN-002 · 2026-09-25 · Hinge API in SwiftUI
**Fact:** The iOS 27.1 SDK declares:

```swift
@available(anyAppleOS 27.1, *)
extension View {
  func onHingeChange(isEnabled: Bool = true,
                     _ action: @escaping (_ oldContext: DeviceHingeContext,
                                          _ newContext: DeviceHingeContext) -> Void) -> some View
}
struct DeviceHingeContext { var hinge: DeviceHinge? }   // nil where there is no hinge
struct DeviceHinge { var status: DeviceHinge.Status; var angle: Angle }
struct DeviceHinge.Status { static var closed, partiallyOpen, fullyOpen }
```

`DeviceHinge.Status` is a **struct with static values, not an enum**. A `switch` on it needs a `default` branch. The UIKit counterpart (`UIHinge.h`) also has an "unknown" status, which SwiftUI doesn't expose as a named value.
**Evidence:** `SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface` in `iPhoneSimulator27.1.sdk`, around lines 16741–16773 (types) and 24266–24267 (`onHingeChange`). Read 2026-09-25. Matches ROADMAP §3.
**Confidence:** Verified.
**So what for Pop!:** `status` picks the mode (cover or book). `angle` drives curl progress and pop depth. A nil `hinge` means a non-Duo iPhone, so the app falls back to the swipe reader (PRD H5).

### TN-003 · 2026-09-25 · Apple's guidance on hinge angle updates
**Fact:** Apple's doc comment on the hinge angle says the angle is in radians. It also says the update rate and granularity are system policy and can change with system state, so apps shouldn't depend on a particular update frequency or precision. When an app only needs to know closed, partially open or fully open, Apple says to "prefer `status` over the angle".
**Evidence:** `UIKit.framework/Headers/UIHinge.h`, lines 64–67, in the iOS 27.1 simulator SDK. Read 2026-09-25.
**Confidence:** Verified (Apple's own doc comment).
**So what for Pop!:** This is the SDK evidence behind PRD principle 4, "the hinge is for magic, not navigation". Layout follows `status` only, and the angle only drives effects. `PostureMachine` tests should include sparse and irregular angle sequences, not just smooth ones.

### TN-004 · 2026-09-25 · `ArrangementView` for the two-page spread
**Fact:** The SDK declares:

```swift
@available(anyAppleOS 27.1, *)
struct ArrangementView<Primary: View, Secondary: View>: View {
  init(@ContentBuilder primary: () -> Primary, @ContentBuilder secondary: () -> Secondary)
}
func arrangementViewStyle(_ style: some ArrangementViewStyle) -> some View
// .split   → SplitArrangementViewStyle,   with .axes(_:)
// .overlay → OverlayArrangementViewStyle, with .axes(_:)
func splitArrangementLayoutRatio(_ ratio: CGFloat?) -> some View
func splitArrangementLayoutRatio(minHorizontal: CGFloat? = nil, idealHorizontal: CGFloat? = nil,
                                 maxHorizontal: CGFloat? = nil, minVertical: CGFloat? = nil,
                                 idealVertical: CGFloat? = nil, maxVertical: CGFloat? = nil) -> some View
```

`primary` and `secondary` are **`@ContentBuilder` closures**, so the call site is `ArrangementView { TextPage() } secondary: { ArtPage() }`. The view has two panes only.
**Evidence:** `SwiftUICore…swiftinterface`, around lines 4596–4627 (split style and ratio), 12783–12802 (overlay style) and 16652–16678 (`ArrangementView`, `arrangementViewStyle`). All are marked `@available(anyAppleOS 27.1, *)`.
**Confidence:** Verified.
**So what for Pop!:** The spread is `ArrangementView` with `.split`. Primary is the text page and secondary is the art page. The system owns the split.

### TN-005 · 2026-09-25 · Reserved regions (fold and camera)
**Fact:** The SDK declares:

```swift
@available(anyAppleOS 27.1, *)
extension GeometryProxy {
  func reservedRegions(kind: ReservedRegion.Kind,
                       options: ReservedRegion.QueryOptions = [],
                       layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]
}
struct ReservedRegion: Identifiable, Hashable, Sendable {
  var id: ID; var kind: Kind; var frame: CGRect; var margins: EdgeInsets; var isActive: Bool
}
// ReservedRegion.Kind:         .occlusion, .division
// ReservedRegion.QueryOptions: .includeInactive
```

The third parameter, `layoutDirectionBehavior` (default `.mirrors`), isn't listed in ROADMAP §3. It's harmless because it has a default.
**Evidence:** `SwiftUICore…swiftinterface`, around lines 4843–4895 (types) and 10290 and 10315 (the method, on both `GeometryProxy` declarations).
**Confidence:** Verified for the signatures. **Inferred** for the meanings: `.division` = the fold and `.occlusion` = the camera come from the names only.
**So what for Pop!:** Text pads by each region's `margins`, and art is placed so faces stay clear of it. The Phase 0.2 probe draws the regions as overlays to confirm what each kind marks.

### TN-006 · 2026-09-25 · UIKit versions of the Duo APIs exist; Pop! doesn't use them
**Fact:** The UIKit headers `UIHinge.h`, `UIHingeInteraction.h` and `UIArrangementViewController.h` exist in the 27.1 SDK. According to `UIHingeInteraction.h`, a disabled interaction doesn't queue hinge updates.
**Evidence:** `UIKit.framework/Headers/` in the iOS 27.1 simulator SDK.
**Confidence:** Verified for UIKit. That SwiftUI's `onHingeChange(isEnabled: false)` behaves the same is **Inferred**.
**So what for Pop!:** None for now; the app is SwiftUI. If the curl is ever paused with `isEnabled: false`, re-read `status` when it's re-enabled rather than expecting missed updates to arrive.

### TN-007 · 2026-09-25 · No cover-display API
**Fact:** The SDK has no dedicated API for the outer (cover) screen.
**Evidence:** PRD §11 and ROADMAP §3 (the builder's SDK check). Re-checked 2026-09-25: searching `SwiftUICore…swiftinterface` and `UIKit.framework/Headers` for "CoverDisplay", "CoverScreen", "OuterDisplay" and "OuterScreen" found nothing.
**Confidence:** Verified (the API is absent under those names).
**So what for Pop!:** When `status` is `.closed`, show the cover view, assuming the app then runs on the outer screen. How the simulator presents this is still open (Phase 0.1).

### TN-008 · 2026-09-25 · Unknown: does the simulator deliver a continuous hinge angle?
**Fact:** Not known yet. The simulator's fold controls might only give set postures.
**Evidence:** PRD §11 and §12, ROADMAP task 0.1.
**Confidence:** Open question.
**So what for Pop!:** Curl and pop-up depend on a continuous angle. The fallback is an in-app hinge slider (one of the three `HingeSource` versions) that feeds the same `PostureMachine`.

### TN-009 · 2026-09-25 · Reactor Orbis has no Swift SDK, so it runs in a `WKWebView`
**Fact:** Orbis Stable documents a JavaScript SDK (`@reactor-team/js-sdk` 3.x) and a Python one. Dynamic also lists raw WebRTC. There is no Swift SDK.
**Decision:** Bundle the JS SDK into the app and host it in a `WKWebView` (never loaded from the web), behind the Swift `LiveScene` protocol. `StillPanScene` is the native fallback.
**Evidence:** Reactor's docs and the teammate's Orbis hackathon starter (ROADMAP §3 and §4).
**Confidence:** Vendor docs; Decision (accepted in ROADMAP §2).
**So what for Pop!:** Orbis is one implementation of `LiveScene`, so it could be swapped for native WebRTC or a different vendor.

### TN-010 · 2026-09-25 · Orbis control rules and the per-page sequence
**Fact:** `set_image` only works before `start`; changing the image needs `reset` then `start`. `set_prompt` works mid-run and takes effect at the next chunk (~1.8 s). The first chunk after `start` contains no frames.
**Decision:** When a page is shown fully open, run `reset → set_image(page still) → set_prompt(page motion prompt) → wait for conditions_ready → start`. Keep the still on screen until the first frames arrive. A drift guard re-anchors, or pauses and holds the frame, after *T* seconds; *T* is TBD (measured in Phase 0.3). Orbis audio is off during creation. A flip runs the same sequence for the next page.
**Evidence:** Reactor's docs and the teammate's starter (ROADMAP §2 and §3).
**Confidence:** Vendor docs; Decision (accepted).
**So what for Pop!:** Every page gets a fresh animation from its own picture (PRD P3–P5), with no black frames.

### TN-011 · 2026-09-25 · Orbis sessions and tokens
**Fact:** A session takes **minutes** to start. Tokens come from Reactor's public token endpoint (`POST https://api.reactor.inc/tokens`), last up to 6 h, and are capped by a maximum number of sessions. A failed connect can leave a session running that only the API key can delete.
**Evidence:** Reactor's docs and the teammate's starter (ROADMAP §3).
**Confidence:** Vendor docs.
**So what for Pop!:** Warm up the session when a New Book starts (for the demo, T-60 min). Tokens are minted server-side (`reactor-token`). The `reactor-sessions` function cleans up stray sessions at launch. There's a KILL switch. A leaked session bills until it's killed.

### TN-012 · 2026-09-25 · Orbis Stable vs Dynamic: specs and price
**Fact:**

| | Native output | Delivered | Price | Notes |
|---|---|---|---|---|
| **Stable** | 832×480 at 18 fps | up to 4K | **$0.582/min** | — |
| **Dynamic** | 640×368 | — | **$1.254/min** | Can change resolution live; sessions up to ~60 min |

It's **unclear** whether billing starts at connection or at generation.
**Evidence:** Reactor's docs (ROADMAP §3).
**Confidence:** Vendor docs.
**So what for Pop!:** D3 recommends Stable: higher resolution at under half the price. A 15-minute book costs 15 × $0.582 = **$8.73** in Orbis time on Stable (the PRD's "~$9") and $18.81 on Dynamic. If billing starts at connection, each warm-up minute adds $0.582. Real cost per book: TBD (measured in Phase 0.3 and Phase 5).

### TN-013 · 2026-09-25 · Orbis input images should be 16:9
**Fact:** Orbis works best with 16:9 input images; other shapes get squashed.
**Evidence:** Reactor's docs (ROADMAP §3).
**Confidence:** Vendor docs.
**So what for Pop!:** Gemini generates 16:9 art with the important content in the centre, which is then cropped to the right page. The same rule keeps faces away from the reserved regions (TN-005).

### TN-014 · 2026-09-25 · Vision background removal reportedly doesn't run in the simulator
**Fact:** `VNGenerateForegroundInstanceMaskRequest` reportedly doesn't run in the Simulator, apparently because it needs the Neural Engine.
**Decision:** Don't segment. Generate pop-up layers directly: a background plate plus character cutouts on a flat colour that Core Image keys out into alpha PNGs, prepared early for each page.
**Evidence:** Apple Developer Forums reports (ROADMAP §3). The exact thread link is TBD. We haven't run it in our simulator.
**Confidence:** Reported; Decision (accepted in ROADMAP Phase 4).
**So what for Pop!:** The pop-up doesn't depend on hardware the simulator lacks. It's also faster at flip time, because the layers already exist.

### TN-015 · 2026-09-25 · OpenAI text-to-speech has no word timings, so read-along uses `AVSpeechSynthesizer`
**Fact:** OpenAI text-to-speech doesn't return word timings. `AVSpeechSynthesizerDelegate` has `speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)`, which reports the character range about to be spoken.
**Evidence:** OpenAI's docs (ROADMAP §3). The delegate method is declared in `AVFAudio.framework/Headers/AVSpeechSynthesis.h`, line 306, in the iOS 27.1 simulator SDK (available since iOS 7).
**Confidence:** Vendor docs (OpenAI); Verified (Apple delegate).
**So what for Pop!:** Read-along word highlighting (C1, Phase 8) is driven by on-device speech callbacks.

### TN-016 · 2026-09-25 · OpenAI Realtime transcription with short-lived client secrets
**Fact:** OpenAI Realtime supports transcription-only sessions, using short-lived client secrets minted by our server.
**Evidence:** OpenAI's docs (ROADMAP §3).
**Confidence:** Vendor docs.
**So what for Pop!:** The `stt-token` function mints the secret, and the app never holds the OpenAI key. Apple on-device speech is the fallback; whether it works in the simulator is TBD (measured in Phase 0.5).

### TN-017 · 2026-09-25 · Where keys and config live
**Fact:** The Reactor, Gemini and OpenAI API keys live only in `supabase/functions/.env` and in Supabase secrets. On Day 0, each key returned HTTP 200. The app-side Supabase URL and publishable key live in `config/Supabase.local.xcconfig`. The Supabase project ref lives in `supabase/.temp/`. All three paths are git-ignored. The `.env` is readable only by its owner.
**Evidence:** Run on 2026-09-25 in the main checkout. `git check-ignore -v` matches `.gitignore` lines 5 (`supabase/functions/.env`), 6 (`supabase/.temp/`) and 7 (`config/*.local.xcconfig`). `stat` shows `supabase/functions/.env` as `-rw-------`. HTTP 200s: ROADMAP §1. No values were printed.
**Confidence:** Verified.
**So what for Pop!:** Keys stay on the server, and the app only receives short-lived tokens. This is the basis of the privacy story in PITCH.md.

### TN-018 · 2026-09-25 · Decision: the hinge drives effects only, never layout
**Decision:** `HingeSource` emits `(status, angle)` in three versions: Duo (`onHingeChange`), a debug slider, and none (swipe). `PostureMachine` is a pure function from a stream of angles to effects: curl progress, turn committed or cancelled, pop depth, closed. It's built test-first. Layout depends only on posture and user toggles.
**Evidence:** PRD principle 4 and requirement H4, ROADMAP §2, and Apple's doc comment (TN-003).
**Confidence:** Decision (accepted).
**So what for Pop!:** Layout never jitters with the angle. The same machine runs from the simulator's hinge controls or the slider, and it can be unit-tested with scripted angle sequences.

### TN-019 · 2026-09-25 · Decision: the motion prompt template keeps each animation on its page
**Decision:** Orbis prompts use one fixed template per page: `"The same {SCENE}, the same {CAMERA: locked-off, still}. {ONE GENTLE MOTION CLAUSE}. Nothing new enters the scene. Continuous slow motion, no cuts."` `SCENE` comes only from this page's text and illustration. `SCENE` and `CAMERA` stay identical within the page, and only the motion clause varies. A unit test checks that the template stays byte-identical.
**Evidence:** ROADMAP §2 and §8. The pattern is the teammate's continuity lesson (`lib/scene.ts` in the starter).
**Confidence:** Decision (accepted).
**So what for Pop!:** This is how PRD P4 ("the animation stays relevant") is enforced. Drift is measured in Phase 0.3.

### TN-020 · 2026-09-25 · Vendor stack as planned
**Decision:** Reactor Orbis for animation. Google Gemini for illustrations, pop-up layers and animation prompts. OpenAI for speech-to-text, the story model, moderation and narration. Supabase for auth, Postgres, Storage and the Edge Functions that hold the keys. Sentry for crash and performance monitoring, with personal data scrubbed. RevenueCat for the paywall.
**Evidence:** PRD §11, ROADMAP §2.
**Confidence:** Decision. Gemini covering images only is **assumed** (D7, to confirm now).
**So what for Pop!:** Keys for all three AI vendors sit behind Supabase functions (TN-017).

### TN-021 · 2026-09-25 · Snapshot of open decisions (PRD §13, ROADMAP §10)
**Decision:** The status of each decision on 2026-09-25. Each one gets its own entry when it's made.

| # | Decision | Recommendation | Status | Decide by |
|---|---|---|---|---|
| D1 | How fold-to-turn and fold-to-pop-up coexist | One continuous motion: past the turn threshold commits the turn; keep folding to ~90° and the new page pops up; opening flat plays its animation | Proposed | Gate G0 |
| D2 | What "page appears in under 5 s" means | Text plus placeholder ≤ 5 s; still ≤ 10 s; animation ≤ 5 s after the flip | Proposed | G0 |
| D3 | Orbis Stable vs Dynamic | Stable (TN-012) | Proposed | G0 (Phase 0.3 spike) |
| D4 | Record each page's clip for rereads and video export | Yes, if recording works in the `WKWebView` | Proposed | G0 |
| D5 | Pro pricing | TBD after measuring the real cost per book | Open | After Phase 5 |
| D6 | Kids Category listing | No: the parent is the user | Proposed | Before any public release |
| D7 | Gemini's role | Images and animation prompts only | Assumed | Now |
| D8 | Timeline and demo date | No deadline; build the full scope, including every cut-list feature | **Resolved 2026-09-25** | — |

**Evidence:** PRD §13, ROADMAP §10.
**Confidence:** Decision (D1–D7 proposed or open; D8 resolved).
**So what for Pop!:** D1, D3 and D4 shape the demo script and the unit economics in PITCH.md. D5 is the biggest open business question.

### TN-022 · 2026-09-25 · The Duo simulator reports 466×678 pt at first boot
**Fact:** The first time it booted, the iPhone Duo simulator reported a screen of 466×678 points. We don't yet know which posture or screen (open spread or outer cover) that size belongs to.
**Evidence:** ROADMAP §1, updated by the builder in commit `80f3c2f` (Claude Code's simulator panel attached to the Duo).
**Confidence:** Verified (builder, simulator panel) for the size. The posture is unconfirmed.
**So what for Pop!:** It's the first real number for page layout. The Phase 0.1 and 0.2 probes should record the point size in each posture, alongside the reserved regions (TN-005).

### TN-023 · 2026-09-25 · ROADMAP §3 now matches the SDK
**Fact:** The builder re-checked TN-002 to TN-005 against the SDK on their own and corrected ROADMAP §3 and Phase 1. The roadmap now shows `ArrangementView` with `@ContentBuilder` closures (two panes only), `reservedRegions` with `layoutDirectionBehavior`, `DeviceHinge.Status` as a struct (so a `switch` needs a `default`), and a note that the angle is in radians. The "not listed in ROADMAP §3" note in TN-005 no longer applies.
**Evidence:** Commit `d3f48c0`. The builder also re-read `UIHinge.h`, which says the angle is in radians and that its update rate is "system policy".
**Confidence:** Verified (two independent SDK reads).
**So what for Pop!:** The pitch, the tech log and the roadmap now agree on the Duo APIs. Phase 1's `PostureMachine` tests cover sparse and irregular angle sequences.

### TN-024 · 2026-09-25 · Decision: saved books replay exactly (P-01 accepted; D4 resolved)
**Decision:** Brian accepted P-01, so parents drive creation and a saved book replays exactly as it was made. That makes recording each page's clip **required** (D4 resolved). New units: `BookStore` saves a finished book (rows, pictures, layers, clips) and keeps a copy on the device. `ClipReplayScene`, a third `LiveScene` implementation, plays a saved page's recorded clip. `ReactorWebScene` also records each page's clip while the final version of that page plays. Showing a saved book makes no generation calls and works without a network. This supersedes the D4 row of TN-021.
**Evidence:** PRD v2 (principle 6, S13, B1–B2, §11 "Clip recording", D4) and ROADMAP v2 (§2 units, Phase 0.3, Phase 3, the new Phase 5 "Save and show", with the exit test "identical with Reactor off and network disconnected"), commit `5c22f0d`. P-01 is marked accepted in `docs/PIVOTS.md`.
**Confidence:** Decision (accepted). **Unverified:** whether a clip can be recorded from the `WKWebView` at all. Phase 0.3 tries in-page recording first, then native capture of the web view. If neither works, a saved book shows the still and re-animates it live from the same picture and prompt, which is close but not exact, and not free.
**So what for Pop!:** Orbis cost is paid once, while a book is made. Showing it costs $0 in Orbis time. Clip storage becomes a new per-book cost, TBD (measured in Phase 5). The demo's network fallback is now a saved golden book on the device.
