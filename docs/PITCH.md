# Pop! — Pitch

*Owner: **Pop! · Pitch & Tech Log** · Updated 2026-09-25 · Sources: [PRD.md](PRD.md), [ROADMAP.md](ROADMAP.md), [TECH_NOTES.md](TECH_NOTES.md)*

> **Ground rules.** Every number here matches the PRD, the ROADMAP or TECH_NOTES. Anything we haven't measured says **TBD (measured in Phase N)**. We have no user research yet (PRD §2), so every "why" below is a hypothesis we plan to test. This pitch follows the **current PRD**. Framing that depends on a *proposed* pivot is marked "depends on P-NN" and lives in the Ideas inbox until Brian accepts it.

---

## 1. One-liner

> **"The only screen time that happens with your kid, not instead of them."**

Pop! is a picture book that a parent and child make together, live, on the iPhone Duo. The parent sets it up and guides the story. The kid tells it out loud. The book writes, illustrates and animates itself one page at a time.

## 2. The 30-second version

> Bedtime stories are the best thing parents do with their kids, but they leave nothing behind, and tired parents run out of ideas. Kids' apps go the other way: one child, alone, competing with the parent for attention.
>
> Pop! puts the parent back in the story. The parent picks the kind of book: make-believe, a topic to learn, or a real moment like a first day at school. Then parent and kid tell it together, out loud, and the iPhone Duo becomes the book. The words appear on the left page. The picture paints itself on the right, then comes alive. Fold the phone to turn the page. Tilt it to 90° and the characters pop up out of the spine. Close it, and you have a finished book with your kid's name on the cover.
>
> It works now because two new things arrived together: Apple's foldable iPhone, and generative video that runs live.

## 3. The problem

- Parents of 3–8 year olds want screen time that builds connection and imagination.
- Most kids' apps are designed for one child alone, and they compete with the parent for attention.
- A made-up bedtime story is the opposite: shared and creative. But it leaves nothing behind, and a tired parent often runs out of ideas.
- Nothing today turns a family's spoken story into a finished, illustrated book as they tell it, with the parent in the loop.

*How we'll check this:* 5–10 parent interviews, plus observed sessions with a real child that measure time on task and pages per book (PRD §2).

## 4. Why now

1. **The iPhone Duo.** iOS 27.1 adds a hinge API with a posture status and a continuous angle, a two-pane `ArrangementView`, and reserved regions for the fold and camera (TN-002 to TN-005). A phone that opens like a book is the natural home for a book. A new form factor also needs apps that show what the fold is *for*.
2. **Generative video that runs live.** Reactor's Orbis turns a still picture into streaming video at 18 fps for about $0.58 a minute (TN-012). "The picture comes alive" becomes a live effect instead of a render job.
3. **Fast speech and image models.** Streaming transcription runs on short-lived tokens that our server mints (TN-016), and image models accept a character reference. How consistent the characters stay is TBD (measured in Phase 0.4).

## 5. How it works

### Two people, two roles

| | Parent | Kid (3–8) |
|---|---|---|
| **Role** | Payer, account owner and co-creator | Co-creator |
| **Does** | Picks the mode (Imagine, Learn, Real life), the topic or real moment, the reading level and content filters. Guides the story on the **parent's turn** and reads along | Tells the story out loud on the **kid's turn**. Taps, draws, listens |
| **Never does** | — | Settings, purchases or sharing (all behind a parental gate) |

The **kid's turn / parent's turn** toggle (PRD S2, a must-have) tells the story engine who is speaking. On the parent's turn, what the parent says is treated as guidance, not story text, unless the parent explicitly narrates.

### The magic moments

**Rule: the hinge is for magic, not navigation.** Folding drives effects. Layout never moves with the angle.

| Moment | What the family sees | What's happening underneath |
|---|---|---|
| **Talk** | Words appear on the left page as they speak. The right page shows "painting…", then the picture, then the picture starts to move | Streaming speech-to-text → story engine (reading level, page breaks, a running story bible) → Gemini illustration → Orbis live video anchored on that illustration |
| **Change your mind** | "No, it was a dragon!" and the page redraws | The story engine revises the current page, and superseded work is cancelled |
| **Fold to turn** | The page lifts and curls with the hinge. Let go early and it falls back; push past and it turns. The new page starts its own animation | Hinge angle → `PostureMachine` → curl progress. A committed turn starts a fresh Orbis sequence for the new page (TN-010) |
| **Tilt to ~90°** | The characters rise out of the spine in front of the background, deeper as the angle grows. Open flat and they fold back | Layers made ahead of time (a background plate plus character cutouts) are rendered in 3D, with depth following the angle (TN-014) |
| **Close** | The cover reads *"The Turtle Who Flew, by Maya"*, and the book goes on the shelf | Hinge `status` becomes `.closed` → cover view, with an AI-generated title and cover art |

**Gesture model (D1, recommended; decided at Gate G0):** one continuous motion. Fold past the turn threshold to commit the turn, keep folding to ~90° and the new page pops up, then open flat to play its animation.

## 6. Live demo script (3 minutes)

**Must-haves shown:** live generation, page curl, pop-up. The parent is on stage as co-creator. Closing to finish is a bonus beat once Phase 5 ships.

**Setup** (ROADMAP §9): at T-60 min, open a New Book to warm up Orbis (it takes minutes). At T-15 min, do a rehearsal pass. Use headphones so the animation's sound doesn't reach the mic, and a wired connection or a hotspot. The demo runs in the **iPhone Duo simulator on a Mac**. The hinge comes from the simulator's fold controls, or from the in-app hinge slider if the simulator only gives set postures (TN-008). Voices go into the Mac mic. Two voices work best: one presenter as the parent, one as the kid.

| Time | On screen | Say | Capture |
|---|---|---|---|
| 0:00–0:15 | Bookshelf, phone fully open | "Bedtime stories are the best screen-free thing we do with our kids. Pop! is the only screen time that happens *with* your kid, not instead of them." | 📸 **S1** bookshelf |
| 0:15–0:30 | **Parent:** New Book → Imagine. The kid's first name and reading level come from the parent's profile | "The parent sets it up: make-believe tonight. Learn and Real-life modes are for when the parent has a goal. The animation engine has been warming up since before we walked on stage." | — |
| 0:30–1:05 | **Kid:** *"Once there was a turtle who wanted to fly."* Text appears on the left. The right page shows "painting…", then the still, then the animation | "Her words, cleaned up to a five-year-old's reading level. Now the picture… and now it's alive. The animation only shows what the page says: no new characters, and the camera stays still." | 🎥 **R1** the hero clip: sentence → text → still → animation. Overlay the real timings once measured (TBD, Phase 2 and 3) |
| 1:05–1:25 | **Parent** flips the toggle to parent's turn: *"What if a bird offers to teach him?"* **Kid** takes it from there: *"A bird named Pip showed him how to flap!"* | "The parent steers, and it doesn't land on the page. The kid runs with it. Page two is being prepared while they talk." | 🎥 **R2** parent's turn → kid's turn |
| 1:25–1:55 | Fold slowly: the page lifts and curls. Release early and it falls back. Fold past the threshold and it turns. Page two starts its own animation | "The hinge *is* the page. Let go and it falls back. Push past and it turns. Page two was ready before we got here, so there's no waiting." | 🎥 **R3** curl following the hinge |
| 1:55–2:25 | Keep folding to ~90°: the characters rise out of the spine, deeper as the angle grows. Open flat: they fold back and the animation resumes | "And like any good pop-up book…" *(pause and let it land)* | 🎥 **R4** pop-up · 📸 **S2** best still for a deck cover |
| 2:25–2:45 *(bonus, Phase 5)* | Close → the cover: *"The Turtle Who Flew, by Maya"* | "Close it and it's finished. Their book, her name on the cover, on the shelf to read again." | 📸 **S3** cover screen |
| 2:45–3:00 | Open back to the spread | "The only screen time that happens with your kid, not instead of them." | — |

**Swap-ins:**
- *If revision ships (S5):* in place of the parent's-turn beat, the kid says *"No, it was a dragon!"* and the page regenerates (🎥 **R5**).
- *Apple audience:* in place of the parent's-turn beat, spend 15 seconds on the hidden debug overlay: hinge status and angle live, the Orbis chunk counter, the credit meter and KILL (📸 **S4**).
- *Depends on P-01:* if Brian accepts P-01, the hero moment becomes "a parent makes a lesson book in 2 minutes and the kid reads it". The script gets re-framed then; see the Ideas inbox.

**If something breaks** (ROADMAP §9, PRD §9):
- *Reactor fails:* the still-image pan-and-zoom takes over automatically. Keep talking: "the illustrator is still painting."
- *Network fails:* switch on demo replay mode (Phase 9).
- *Speech fails:* Apple on-device speech is the fallback, and the app says a gentle "let's try that again" line.
- *Simulator hinge is jumpy:* switch to the in-app hinge slider.

### Media shot list (capture when each piece is built)

| ID | What | Available from | Where it goes |
|---|---|---|---|
| S1 | The spread: text left, art right, clear of the fold and camera | Phase 1 (mock) / Phase 2 (real) | §2 and the deck's product slide |
| R1 | Speech → text → still → animation in one take, with timings | Phase 3 | §6 hero clip; top of the VC deck |
| R2 | Parent's turn → kid's turn, with the parent's nudge kept off the page | Phase 2 | §5 "Two people, two roles"; VC "Who pays" |
| R3 | Curl following the hinge, falling back and committing | Phase 1 | §5 "Fold to turn"; Apple section |
| R4 / S2 | Pop-up at ~90° | Phase 4 | §5; deck cover |
| S3 | Cover on the closed screen | Phase 5 | §5 "Close" |
| S4 | Debug overlay (hinge angle, chunk, credit meter) | Phase 3 | §8, Apple section |
| R5 | "No, it was a dragon!" revision | Phase 2 (if S5 ships) | §9 "Does the AI take over?" |
| R6 | Kill Reactor mid-page → still-pan, no error shown | Phase 3 | §9 "What if the video service goes down?" |

---

## 7. For VCs

### Market

- **Buyer, account owner and co-creator:** parents of 3–8 year olds. **Co-creator:** the kid. **Not for:** kids alone, classrooms, kids over ~9.
- **Wedge:** iPhone Duo owners with young kids, where the fold interactions are the hero.
- **Expansion:** every iPhone via the single-page reader (PRD H5), then iPad and Android (out of scope for now).
- **Size: TBD.** Method: households with a child aged 3–8 on a Duo (then any iPhone) × share that make a book in a month × conversion to Pro × price. Fill this in only with sourced numbers.

### Who pays

**Parents, and they're in the room.** The parent isn't just the card on file. They set up every book, guide it on the parent's turn, and read along. Learn mode (a topic with verified facts) and Real-life mode (preparing a child for a real event) give parents a reason to start a book beyond "entertain my kid". The kid never sees purchases, settings or sharing; all three sit behind a parental gate (K4).

### Business model

- **3 free books, then Pro** (K5). **Depends on P-02 / D5.** The Pro price is **TBD**, set after measuring the real cost per book (D5, after Phase 5). Whether Pro stays "unlimited" is Brian's call (P-02, proposed).
- Possible add-ons (printed book, gifting) are in the [Ideas inbox](#10-ideas-inbox). They're not in the plan.

### Unit economics (honest version)

The biggest cost is live animation. Orbis Stable is billed per second at **$0.582 a minute** (TN-012).

| Live animation per book | Orbis Stable ($0.582/min) | Orbis Dynamic ($1.254/min) |
|---|---|---|
| 5 min | $2.91 | $6.27 |
| 10 min | $5.82 | $12.54 |
| **15 min (the PRD's planning case)** | **$8.73 ≈ $9** | $18.81 |

**Not in that number yet:**
- **Warm-up.** A session takes minutes to start, and we don't know yet whether billing starts at connection or at generation. If it's at connection, each warm-up minute adds $0.58. TBD (measured in Phase 0.3).
- **Everything else per book:** Gemini illustrations, layers and cover; OpenAI transcription, story model, moderation and narration; Supabase storage. TBD (measured in Phase 2).
- **The App Store commission** on Pro revenue.

**What that means, unmitigated:**
- Three free books can cost **~$26** in animation alone (3 × $8.73) for each family that uses all three, before we earn anything.
- A family making one book a week (four a month) costs **~$35 a month** in animation alone (4 × $8.73). Pro as "unlimited" can't carry that without the mitigations below, which is why P-02 asks whether to keep "unlimited". The mitigations are part of the business model, not polish.

**Mitigations:**
1. **Record once, replay for free.** Save each page's clip (D4, pending the Phase 0.3 recording test). Rereads, PDF sharing and video export then cost $0 in Orbis time. *Hypothesis:* rereads are where a picture book gets most of its use.
2. **Only pay for what's on screen.** Use one session per book. Only animate the page that's open. Close idle sessions on purpose. The server cleans up stray sessions, because a failed connect can leave one billing (TN-011).
3. **Stable, not Dynamic:** under half the price per minute (D3).
4. **Cap live seconds per page** *(proposal)*: animate live for a short while, then loop the recorded clip.
5. **Tiered free books** *(proposal)*: free books use the still-image pan (the existing fallback) on most pages and live animation on the first page.
6. **Price Pro on measured cost** (*depends on P-02 / D5*). A fair-use allowance may beat "unlimited". PRD K5 still says unlimited, and the change is logged as P-02 (proposed) for Brian to decide.
7. **Prices may fall.** Per-minute prices for generative video may drop over time. We don't bank on it.

**North-star cost metric:** cost per finished book, TBD (measured after Phase 5). It's already a tracked product metric (PRD §5).

### Moat (honest: early)

We rent the models, and anyone can call them. What we can defend is what we build around them:
1. **Craft on a new form factor.** Curl, pop-up and close-to-finish tuned to the Duo's hinge. It's easy to copy badly and hard to copy well.
2. **The page pipeline.** Page-anchored motion prompts, a drift guard, consistent characters, the next page prepared early, a safety gate at every step, and a 30-transcript red-team set.
3. **The family shelf.** Every book belongs to the family, and the library grows with each one.
4. **Trust with parents.** Calm defaults, no dark patterns, and we don't keep voices.

**What we don't claim:** a data moat. We deliberately don't keep kids' audio.

### Risks (the ones an investor will ask about; full list in PRD §12)

| Risk | Why it matters | What we do |
|---|---|---|
| Cost per book (~$9 unmitigated) | Unit economics | The mitigations above; price after measuring (depends on P-02 / D5) |
| Orbis warps faces or drifts off the page | The magic breaks | Gentle motion, locked camera, drift guard. Fallback: animate only the background and keep the characters as crisp cutouts |
| Orbis takes minutes to warm up | The family waits | Warm up when the book starts; show text and stills first |
| One live-video vendor | An outage or a price change | Orbis is one implementation of `LiveScene`, and the still-pan fallback always works (TN-009) |
| Kids' privacy law (COPPA) | Blocks release | Transcribe and discard audio, first name only, parental gate. **Legal review before any public release** |
| Unsafe output reaches a child | Ends trust | Moderation on text, prompts and images; a frame tripwire. Gate: 0 unsafe outputs in a 30-transcript red-team set |
| Small Duo install base | Wedge size | Also runs on every iPhone as a single-page reader |
| Demand is unvalidated | The whole thesis | Parent interviews and observed sessions with kids (PRD §2) |

### The ask

*Placeholder, to be filled in from one source of truth that Brian owns.*
- **Raise:** TBD · **Instrument:** TBD
- **Use of funds:** TBD
- **Milestones it buys:** TBD
- **Team:** two engineers (Brian plus a teammate); bios TBD

---

## 8. For Apple engineers

### Using the iOS 27.1 Duo APIs the way they're meant to be used

1. **The hinge drives effects, never layout.** `onHingeChange(isEnabled:_:)` delivers the old and new `DeviceHingeContext`. `hinge.angle` feeds a pure, unit-tested `PostureMachine` whose only outputs are effects: curl progress, turn committed or cancelled, and pop depth. Layout follows only `hinge.status` (`.closed` → cover, open → spread) and user toggles. Apple's header says angle update rate and granularity are system policy and may change, and to "prefer `status` over the angle" when that's enough (TN-003). So effects degrade gracefully if updates get coarse, and layout never jitters.
   - A nil `hinge` means a device without a hinge, so the app shows the swipe reader (H5). `HingeSource` has three versions: Duo, debug slider, and none.
   - `DeviceHinge.Status` is a struct with static values, not an enum, so our `switch` has a `default` branch (TN-002).
2. **`ArrangementView` for the spread.** `ArrangementView { TextPage() } secondary: { ArtPage() }` with `.arrangementViewStyle(.split)` and `.splitArrangementLayoutRatio(_:)` (TN-004). The system owns the split; we don't hand-roll a two-pane layout.
3. **`reservedRegions` keep text and faces out of the fold and camera.** `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` with `.division` (fold) and `.occlusion` (camera) (TN-005). Text is padded by each region's `margins`. Art is generated at 16:9 with the important content in the centre, then cropped so faces stay clear. *What each kind marks is inferred from the names and gets confirmed in the Phase 0.2 overlay probe.*
4. **No cover-display API, so we don't invent one.** `.closed` shows the cover view, on the assumption that the app runs on the outer screen (TN-007). How the simulator presents this is checked in Phase 0.1.
5. **Live video in a native app.** Reactor has no Swift SDK, so its JS SDK is bundled (never loaded from the web) into a `WKWebView` behind a Swift `LiveScene` protocol, with a native `StillPanScene` fallback (TN-009). If Reactor ships native WebRTC or Swift, only one implementation changes.
6. **Pop-up without the Neural Engine.** Vision's foreground mask reportedly doesn't run in the Simulator (TN-014). So we generate the layers directly (a plate plus cutouts, keyed out with Core Image) and render them with SwiftUI 3D transforms. The layers exist before the flip, which is how we aim to have them rising within 300 ms of the pop angle (target; TBD, measured in Phase 4).
7. **Read-along timing on-device.** OpenAI text-to-speech has no word timings, so highlighting uses `AVSpeechSynthesizerDelegate`'s `willSpeakRangeOfSpeechString` callback (TN-015).

### Privacy by design

- **Audio** is streamed for transcription and never stored.
- **The only personal data** is the kid's first name.
- **What's saved:** book text, pictures and, if D4 ships, animation clips.
- **Keys** stay on the server (Supabase Edge Functions and secrets). The app only receives short-lived tokens: an OpenAI Realtime client secret and a Reactor token, both minted server-side (TN-016, TN-011, TN-017).
- **Monitoring** reports crashes and performance with personal data scrubbed (K6).
- **Parental gate** before settings, purchases and sharing (K4).
- **Not a Kids Category app** (D6, recommended): the parent is the user and the account owner. This gets revisited before any public release.

### Built and demoed in the simulator only

- There's no physical Duo. The build uses Xcode 27.1 beta (27A9269), the iOS 27.1 simulator and the iPhone Duo device (TN-001).
- The mic is the Mac's. There's no camera, haptics or motion sensors. Pictures come in only through finger drawing or the photo picker.
- Whether the simulator delivers a continuous hinge angle is unverified until Phase 0.1. The fallback is an in-app hinge slider that drives the same `PostureMachine` (TN-008).
- Beta Xcode builds can't be submitted to the App Store.

---

## 9. Tough questions

| Question | Answer |
|---|---|
| **"Isn't this just more screen time?"** | It's built for two people: the parent sets up and guides the book, the kid tells it, and it ends with a book you keep. We measure books finished together, not minutes on screen. |
| **"Who's the customer, the parent or the kid?"** | The parent. They pay, own the account, pick the mode and guide the story. The kid is the co-author. |
| **"$9 of video per book. How is this a business?"** | $9 is the unmitigated case of 15 live minutes. We record each clip once so rereads are free, animate only the open page, use Stable, and price Pro on the measured cost after Phase 5. Whether Pro stays unlimited is an open decision (P-02 / D5). We'll show the real number, not a guess. |
| **"What stops OpenAI, Google or Apple from doing this?"** | Nothing stops them from building a story generator. What's hard is the co-creation loop between a parent and a five-year-old, the fold interactions, and safety you can trust. Big platforms build general tools; we build one narrow thing very well. Early on, speed and craft are the moat. |
| **"Is it safe for a four-year-old?"** | Every page's text, art prompt, animation prompt and picture passes a kid-safe check before the child sees it. Animation prompts come only from checked content, and sampled frames act as a tripwire back to the still. Our gate is 0 unsafe outputs in a 30-transcript red-team set. A failure looks like "the illustrator is still painting…" |
| **"You're recording kids' voices?"** | No. Audio is streamed for transcription and discarded. We keep a first name and nothing else personal. There's a legal (COPPA) review before any public release. |
| **"Have you tested with kids?"** | Not yet. Next come 5–10 parent interviews and observed sessions that measure time on task and pages per book. |
| **"Why the Duo? Hardly anyone has one."** | The Duo is where the magic is, and that's our wedge, not our ceiling. The whole app also runs on any iPhone as a single-page reader. |
| **"Why live video instead of a pre-rendered clip?"** | Pages change as the family talks ("no, it was a dragon!"). With a warm session, a new page is a `reset` plus a new image, not a new render job. Time to first frame is TBD (measured in Phase 0.3). We also record clips, so rereads don't need live video at all. |
| **"What if the video service goes down mid-story?"** | The still picture with a slow pan-and-zoom takes over automatically, and nobody sees an error. It reconnects with backoff, and there's a kill switch. |
| **"Does the AI take over the story?"** | No. The family leads, and the AI only makes it coherent, safe and readable. The kid's-turn / parent's-turn toggle keeps a parent's nudges out of the story text. |
| **"Does the animation go off-script?"** | The prompt is built only from this page's text and picture, with a locked camera, one gentle motion, and "nothing new enters the scene". A drift guard re-anchors it. Drift at 30 s and 60 s is measured in Phase 0.3. |
| **"How fast is it?"** | Targets (p50): page text ≤ 2.5 s after the sentence ends; text plus placeholder ≤ 5 s; still ≤ 10 s; animation ≤ 5 s after a flip. Measured numbers: TBD (Phase 2 and 3). |
| *Apple:* **"Why doesn't the angle drive layout?"** | Your header says angle updates are system policy and can change rate and precision. Layout tied to the angle would jitter. `status` drives layout, and the angle drives effects only. |
| *Apple:* **"Why not the Kids Category?"** | The parent owns the phone and the account, and the kid creates alongside them. The Kids Category also restricts third-party analytics such as Sentry. It's an open decision (D6), revisited before any public release. |
| *Apple:* **"A web view inside a native app?"** | Reactor ships no Swift SDK. The JS is bundled, never loaded remotely, and sits behind a Swift protocol, so it can be swapped for native WebRTC later. |
| *Apple:* **"Did you run it on a real Duo?"** | No, only in the simulator. The hinge comes from the simulator's controls or an in-app slider. We don't use haptics or motion sensors. |

---

## 10. Ideas inbox

New pitch angles go here. Status: **new** · **used** (moved into the pitch) · **parked** · **depends on P-NN** (waiting on a proposed pivot). Ideas that would change product scope go to the **Pop! · Pivots & Ideas** session, not here.

| Date | Idea | Audience | Status |
|---|---|---|---|
| 2026-09-25 | **Parent-first framing: "a parent makes a lesson book in 2 minutes."** The parent drives creation and ties a lesson into a story about what their kid loves; the kid can join in. This would lead the pitch with the payer's job-to-be-done, and the demo's hero moment would become "a parent builds a lesson book, the kid reads it". | Both | **depends on P-01** (proposed). Re-frame §1, §2, §5, §6 and §7 if Brian accepts it |
| 2026-09-25 | **Printed hardcover** of a finished book as an upsell beyond Pro (PDF export, B3, is the base) | VC | new |
| 2026-09-25 | **Real-life mode for professionals:** pediatric dentists and child therapists use it to prepare kids for real events (a B2B2C angle) | VC | new, would need a Pivots review |
| 2026-09-25 | **Grandparent gifting:** share a finished book as a video (B4) | VC | new |
| 2026-09-25 | **"The fold as a storytelling device":** posture is a story mechanic, not a UI split. A strong angle for an Apple design or developer talk | Apple | new |
| 2026-09-25 | **Bilingual books:** the story language is already in the data model | VC | new |
| 2026-09-25 | **Cost as a feature:** clips are recorded once, so rereads are instant, free and could work offline | Both | new |
