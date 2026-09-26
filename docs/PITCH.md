# Pop! — Pitch

*Owner: **Pop! · Pitch & Tech Log** · Updated 2026-09-25 · A hackathon-style pitch, not a release: **everything is free** (CLAUDE.md, "What this is") · Sources: [PRD.md](PRD.md), [ROADMAP.md](ROADMAP.md), [TECH_NOTES.md](TECH_NOTES.md)*

> **Ground rules.** Every number here matches the PRD, the ROADMAP or TECH_NOTES. Anything we haven't measured says **TBD (measured in Phase N)**. We have no user research yet, so every "why" is a hypothesis.

---

## 1. One-liner

> **"The only screen time that happens with your kid, not instead of them."**

Pop! lets a parent make a picture book for their child in minutes, about whatever the child loves. The parent tells it or types it and directs it as it goes, and each page's picture comes alive. Save it and show it to your child exactly as it was made, or make it live with them beside you.

## 2. The 30-second version

> Parents know exactly what their kid loves: dinosaurs, trucks, the cat. Kids hang on every word of a story about that thing. But turning it into a real illustrated book takes skill and time no parent has.
>
> With Pop!, a parent says "a dinosaur story for Maya" and directs it as it goes: "add a friendly dragon", "make it about sharing". Or they tap *You continue* and the AI writes the next page. On the iPhone Duo it's a real book: fold to turn the page, tilt to 90° and the characters pop up out of the spine, close it and it's saved. At bedtime it plays back exactly as it was made.
>
> It works now because two new things arrived together: Apple's foldable iPhone, and generative video that runs live.

## 3. The problem

- Parents of 3–8 year olds know what their child loves and what they want to share with them, but can't turn that into a good illustrated book.
- Made-up bedtime stories leave nothing behind, and tired parents run out of ideas.
- Most kids' apps are built for one child alone, and they hand the parent a generic story.
- **Nothing today turns a parent's idea into a finished, illustrated, animated book about *their* kid in minutes.**

## 4. Why now

1. **The iPhone Duo.** iOS 27.1 adds a hinge API with a posture status and a continuous angle, a two-pane `ArrangementView`, and reserved regions for the fold and camera (TN-002 to TN-005). A phone that opens like a book is the natural home for a book.
2. **Generative video that runs live.** Reactor's Orbis turns a still picture into streaming video at 18 fps (TN-012). We record each page's clip, so a saved book replays for free.
3. **Fast speech and image models.** Streaming transcription runs on short-lived tokens that our server mints (TN-016), and image models accept a character reference. How consistent the characters stay is TBD (measured in Phase 0.4).

## 5. The experience

**One way to make a book.** The parent can make it alone ahead of time or with the child watching and chiming in (on **kid's turn**). The steps are the same; the only difference is who's watching.

**The parent's tools:**
- **Brief:** what the child loves comes from their kid profile. The parent can also ask for anything else, for example a story that teaches sharing or one that prepares them for the dentist.
- **Narrate:** say or type a page, and it's cleaned up to the child's reading level.
- **Direct:** "add a friendly dragon". The page regenerates, and the change carries forward.
- **"You continue":** the AI writes the next page, following the brief and every direction so far.

**Rule: the hinge is for magic, not navigation.** Folding drives effects. Layout never moves with the angle.

| Moment | What the family sees | Underneath |
|---|---|---|
| **Tell or type** | Words on the left page. The right page shows "painting…", then the picture, then the picture starts to move | Speech or typing → story engine → Gemini illustration → Orbis live video anchored on that illustration |
| **Change anything** | "No, make it a dragon!" and the page redraws | The page is revised, and superseded work is cancelled |
| **Fold to turn** | The page curls with the hinge. Let go early and it falls back; push past and it turns | Hinge angle → `PostureMachine` → curl progress; the new page gets a fresh Orbis sequence (TN-010) |
| **Tilt to ~90°** | The characters rise out of the spine, deeper as the angle grows | Pre-made layers (a background plate plus character cutouts) rendered in 3D (TN-014) |
| **Close to save** | The cover reads *"Rex Learns to Share, a story for Maya"* | `.closed` → title and cover art → `BookStore` saves text, pictures, layers and each page's clip |
| **Show it** | It plays exactly as it was made, with the same curl and pop-up | `ClipReplayScene` replays the recorded clips, with no generation and no network (TN-024) |

## 6. Live demo script (3 minutes)

**Hero moment:** a parent makes a book in minutes, and it plays back exactly for the kid. It runs in the **iPhone Duo simulator** on a Mac. The hinge comes from the simulator's controls or the in-app slider (TN-008). Orbis is warmed up at T-60 min. Use headphones and a wired connection or a hotspot. Maya's kid profile ("loves dinosaurs") is set up in advance.

| Time | On screen | Say | Capture |
|---|---|---|---|
| 0:00–0:15 | Bookshelf, phone open | "Every kid has a thing they're obsessed with. Pop! lets a parent turn it into a book." | 📸 S1 |
| 0:15–0:30 | New Book. Brief: dinosaurs, "make it about sharing" | "Maya loves dinosaurs. Tonight I want a story about sharing. That's the setup." | 📸 S2 |
| 0:30–1:00 | Parent (voice): *"Rex had the biggest pile of toys in the valley."* Text → "painting…" → still → it moves | "I just talk. Now the picture… and now it's alive, showing only what the page says." | 🎥 R1 hero clip (overlay timings, TBD Phase 2 and 3) |
| 1:00–1:20 | Typed direction: *"Add a little dinosaur who wants to play."* Then **You continue** | "I can type and direct it, or just say 'you continue'." | 🎥 R2 |
| 1:20–1:45 | Fold: curl, fall back, then turn | "The hinge *is* the page." | 🎥 R3 |
| 1:45–2:10 | Tilt to ~90°: the pop-up. Open flat: they fold back | "And like any good pop-up book…" | 🎥 R4 · 📸 S3 |
| 2:10–2:30 | Close → the cover → the shelf | "Close it and it's saved. Made at lunch, ready for bedtime." | 📸 S4 |
| 2:30–2:50 | KILL on the debug overlay, then open the saved book: identical | "Nothing is generated again. What you save is what they see, even offline." | 🎥 R5 |
| 2:50–3:00 | The spread | "The only screen time that happens with your kid, not instead of them." | — |

**Swap-ins:** *made together*: replace the 1:00 beat with **kid's turn** ("And the little one had a purple tail!"). *Apple audience*: show the hinge angle on the overlay in the 2:30 beat.
**If something breaks:** Reactor fails → the still-image pan takes over automatically. The network fails → open the saved golden book on the device. Speech fails → type. The hinge is jumpy → use the slider.

**Shot list:** S1 bookshelf (Phase 5) · S2 brief (Phase 2) · R1 voice → animation (Phase 3) · R2 direction + You continue (Phase 2) · R3 curl (Phase 1) · R4/S3 pop-up (Phase 4) · S4 cover (Phase 5) · R5 exact replay with Reactor off (Phase 5) · R6 kid's turn (Phase 2) · R7 Reactor killed mid-page → still-pan (Phase 3).

---

## 7. For VCs

**Problem, why now, and the experience:** see §3–§6.

### Why it's technically hard
1. **Live video that stays on the page.** Orbis gets a fresh image and prompt for each page, with a locked camera, one gentle motion, "nothing new enters the scene", and a drift guard (TN-010, TN-019).
2. **Making a book that feels instant.** Text first, then a placeholder, then the still, then the animation. The next page is prepared while the current one is being told. Targets (p50): text ≤ 2.5 s, still ≤ 10 s, animation ≤ 5 s after a flip. Measured: TBD (Phase 2 and 3).
3. **Exact replay.** Each page's live stream is recorded from a web view and replayed natively and offline (TN-024). Recording is unproven until Phase 0.3.
4. **Posture as interaction.** A curl and a pop-up driven by a hinge whose update rate is system policy (TN-003). This is built and tested in the simulator only.
5. **Safety at every step.** Every page's text, prompts and picture pass a kid-safe check, and the parent previews books made ahead. Gate: 0 unsafe outputs in a 30-session red-team set.

### Where it could go
- **Every iPhone:** the single-page reader already runs without a hinge (H5).
- **Make it together from afar:** a grandparent co-creating a book (out of scope today).
- **Kid's drawing as the hero,** read-along narration, and talking characters (on the cut list).
- **Books in more languages:** the story language is already in the data model.

---

## 8. For Apple engineers

1. **The hinge drives effects, never layout.** `onHingeChange(isEnabled:_:)` → `hinge.angle` feeds a pure, unit-tested `PostureMachine` (curl progress, turn committed or cancelled, pop depth). Layout follows only `hinge.status` and user toggles. Apple's header says the angle update rate is system policy, so the tests include sparse and irregular sequences, and to "prefer `status` over the angle" when that's enough (TN-003). A nil `hinge` (no hinge, or a view outside a hierarchy that provides hinge updates) is handled without a hinge: the swipe reader. `DeviceHinge.Status` is a struct, so our `switch` has a `default` (TN-002).
2. **`ArrangementView` for the spread:** `ArrangementView { TextPage() } secondary: { ArtPage() }` with `.arrangementViewStyle(.split)` (TN-004).
3. **`reservedRegions`** (`.division` = a region an element should divide around, the fold; `.occlusion` = a region occluded by an element, the camera; both from Apple's UIKit header comments) pad the text and keep faces out of the fold and camera (TN-005).
4. **Closing is a verb.** `.closed` saves the book and shows its cover. The SDK has no cover-display API (TN-007).
5. **Live video in a native app, recorded for exact replay.** Reactor has no Swift SDK, so its JS SDK is bundled into a `WKWebView` behind a Swift `LiveScene` protocol, with three implementations: `ReactorWebScene` (live, and records clips), `StillPanScene` (fallback) and `ClipReplayScene` (TN-009, TN-024).
6. **Pop-up without the Neural Engine.** Vision's foreground mask reportedly doesn't run in the Simulator, so the layers are generated and keyed out with Core Image (TN-014). The target is layers rising within 300 ms (TBD, Phase 4).
7. **Read-along timing** comes from `AVSpeechSynthesizer`'s `willSpeakRangeOfSpeechString`, because OpenAI's text-to-speech has no word timings (TN-015).

**Privacy by design:** Pop! never stores audio; it's streamed to OpenAI only to transcribe it. The only personal data is the kid's first name and interests. Keys stay on the server, and the app only receives short-lived tokens (TN-011, TN-016, TN-017). Timing logs stay local, with no third-party analytics or crash service.

**Simulator only:** Xcode 27.1 beta (27A9269) and the iPhone Duo simulator (TN-001). No physical Duo, camera, haptics or motion sensors. Whether the simulator delivers a continuous hinge angle is TBD (Phase 0.1), and the fallback is an in-app slider (TN-008).

---

## 9. Tough questions

| Question | Answer |
|---|---|
| **"How does it make money?"** | It's free; we're showing the experience. Generation costs are real and falling, and saved books replay at no cost. |
| **"Isn't this just more screen time?"** | It's made by the parent, for their child, and read together. |
| **"Isn't the parent doing all the work?"** | As much or as little as they want: narrate every page, give a direction, or tap "You continue". |
| **"Is it safe for a four-year-old?"** | Every page passes a kid-safe check before a child sees it, sampled frames act as a tripwire back to the still, and the parent previews books made ahead. |
| **"Are you recording kids' voices?"** | Pop! never stores audio; it's streamed to OpenAI only to transcribe it. What we save is the book (text and pictures, including anything a kid says that becomes story text), a first name and interests. |
| **"Have you tested with parents and kids?"** | Not yet. Parent interviews and observed sessions come next. |
| **"Why live video instead of pre-rendered clips?"** | Pages change with every direction while the book is being made. Once it's saved, each page *is* a recorded clip. |
| **"What if the video service goes down?"** | The still picture with a slow pan-and-zoom takes over automatically. Saved books don't need the service at all. |
| **"Does the animation go off-script?"** | The prompt comes only from this page, with a locked camera and a drift guard. Drift is measured in Phase 0.3. |
| *Apple:* **"Why doesn't the angle drive layout?"** | Your header says angle updates are system policy, so layout tied to the angle would jitter. `status` drives layout. |
| *Apple:* **"A web view in a native app?"** | Reactor ships no Swift SDK. The JS is bundled, never loaded remotely, and sits behind a Swift protocol. Saved books replay natively. |
| *Apple:* **"On a real Duo?"** | No, only in the simulator. |

---

## 10. Ideas inbox

Pitch angles only. Status: **new** · **used** · **parked**.

| Date | Idea | Audience | Status |
|---|---|---|---|
| 2026-09-25 | "Made at lunch, ready for bedtime." | Both | used (§6) |
| 2026-09-25 | "What you save is what they see": exact replay works offline | Both | used (§5, §6) |
| 2026-09-25 | "The fold as a storytelling device": close = save | Apple | new |
| 2026-09-25 | Grandparents co-creating from afar | Both | new (out of scope today) |
