# Pop! — Pitch

*Owner: **Pop! · Pitch & Tech Log** · Updated 2026-09-25 (re-framed for P-01, accepted) · Sources: [PRD.md](PRD.md) v2, [ROADMAP.md](ROADMAP.md) v2, [TECH_NOTES.md](TECH_NOTES.md)*

> **Ground rules.** Every number here matches the PRD, the ROADMAP or TECH_NOTES. Anything we haven't measured says **TBD (measured in Phase N)**. We have no user research yet (PRD §2), so every "why" below is a hypothesis we plan to test. Anything that depends on a *proposed* pivot is marked "depends on P-NN".

---

## 1. One-liner

> **"The only screen time that happens with your kid, not instead of them."**

Pop! lets a parent make a picture book for their child in minutes: a story about whatever the child loves, with a lesson woven in. The parent tells it or types it and directs it as it goes, and each page's picture comes alive. Save it and show it to your child exactly as it was made, or make it live with them beside you.

## 2. The 30-second version

> Every parent is trying to teach something: sharing, brushing teeth, what happens at the dentist. Kids tune out lectures, but they hang on every word of a story about dinosaurs, trucks or their cat.
>
> Pop! lets a parent turn "a dinosaur story that teaches sharing" into a finished, illustrated, animated book in minutes. You tell it or type it. You direct it ("add a friendly dragon"), or tap *You continue* and the AI writes the next page for you, keeping the lesson on track. On the iPhone Duo it's a real book: fold to turn the page, tilt to 90° and the characters pop up out of the spine, close it and it's saved. Then open it at bedtime and it plays back exactly as you made it.
>
> It works now because two new things arrived together: Apple's foldable iPhone, and generative video that runs live.

## 3. The problem

- Parents of 3–8 year olds want to teach their kids things: sharing, brushing teeth, counting, the dentist, a new sibling.
- Kids tune out lectures, but they listen closely to a story about the thing they love.
- Parents know both what their child loves and what their child needs to learn. Turning that into a good illustrated book takes skill and time they don't have.
- Made-up bedtime stories leave nothing behind, and tired parents run out of ideas. Most kids' apps are built for one child alone and hand the parent a generic story.
- **Nothing today lets a parent turn "a dinosaur story that teaches sharing" into a finished, illustrated, animated book in minutes.**

*How we'll check this:* 5–10 parent interviews on whether parents want to author books for their own child, plus observed sessions measuring time on task, pages per book and what the child remembers (PRD §2).

## 4. Why now

1. **The iPhone Duo.** iOS 27.1 adds a hinge API with a posture status and a continuous angle, a two-pane `ArrangementView`, and reserved regions for the fold and camera (TN-002 to TN-005). A phone that opens like a book is the natural home for a book. A new form factor also needs apps that show what the fold is *for*.
2. **Generative video that runs live.** Reactor's Orbis turns a still picture into streaming video at 18 fps for about $0.58 a minute (TN-012). "The picture comes alive" becomes a live effect, and we record each page's clip so a saved book replays for free.
3. **Fast speech and image models.** Streaming transcription runs on short-lived tokens that our server mints (TN-016), and image models accept a character reference. How consistent the characters stay is TBD (measured in Phase 0.4).

## 5. How it works

### One way to make a book, two ways to share it

The flow is the same whether the child is there or not; the only difference is who's watching (PRD §7).

| | **Made ahead** | **Made together** |
|---|---|---|
| **When** | Lunch break, the evening before | Bedtime, a waiting room, before a real event |
| **Who's there** | The parent alone | The parent with the child beside them |
| **The kid** | Sees the finished book, exactly as it was made | Watches it being made and adds ideas on **kid's turn** |
| **Safety extra** | The parent sees every page before the child does (K1) | Every page passes the kid-safe check before it's shown (K1) |

### Who does what

| | Parent (the author) | Kid (3–8) |
|---|---|---|
| **Role** | Author, payer and account owner | Audience and co-creator |
| **Does** | Sets the **kid profile** (first name, reading level, things they love) and a **story brief** per book (which interests, an optional lesson, an optional real moment). Tells or **types** the story, gives **directions**, taps **"You continue"**, and decides when it's finished | Listens and reads along. On **kid's turn**, their words become story content, cleaned up |
| **Never does** | — | Settings, purchases or sharing (all behind a parental gate) |

### The parent's tools

- **Narrate:** say or type a page, and it's cleaned up to the child's reading level.
- **Direct:** "add a friendly dragon", "she should learn to wait her turn". The current page regenerates, and the direction carries into later pages.
- **"You continue":** the AI writes the next page, following the brief, the lesson and every direction so far.
- **Lesson woven in:** each page moves the lesson forward through the story, not a lecture. Factual lessons use curated lesson packs or a fact-check (K2).

### The magic moments

**Rule: the hinge is for magic, not navigation.** Folding drives effects. Layout never moves with the angle.

| Moment | What the family sees | What's happening underneath |
|---|---|---|
| **Tell or type** | Words appear on the left page. The right page shows "painting…", then the picture, then the picture starts to move | Speech-to-text or typing → story engine (brief, lesson, reading level, page breaks, story bible) → Gemini illustration → Orbis live video anchored on that illustration |
| **Change anything** | "No, make it a dragon!" and the page redraws | The story engine revises the page, superseded work is cancelled, and the change carries forward |
| **Fold to turn** | The page lifts and curls with the hinge. Let go early and it falls back; push past and it turns. The new page starts its own animation | Hinge angle → `PostureMachine` → curl progress. A committed turn starts a fresh Orbis sequence for the new page (TN-010) |
| **Tilt to ~90°** | The characters rise out of the spine in front of the background, deeper as the angle grows. Open flat and they fold back | Layers made ahead of time (a background plate plus character cutouts) are rendered in 3D, with depth following the angle (TN-014) |
| **Close to save** | The cover reads *"Rex Learns to Share, a story for Maya"*, and the book goes on the shelf | Hinge `status` becomes `.closed` (or the parent taps Save) → AI title and cover art → `BookStore` saves the text, pictures, layers and each page's recorded clip, with a copy on the device |
| **Show it** | At bedtime, open the book from the shelf. It plays exactly as it was made, with the same curl and pop-up | `ClipReplayScene` plays each page's recorded clip. No generation calls, and it works without a network (S13) |

**Gesture model (D1, recommended; decided at Gate G0):** one continuous motion. Fold past the turn threshold to commit the turn, keep folding to ~90° and the new page pops up, then open flat to play its animation.

## 6. Live demo script (3 minutes)

**Hero moment: a parent makes a lesson book in minutes, and it plays back exactly for the kid.**
**Must-haves shown:** parent-driven live generation, page curl, pop-up, save and show exactly.

**Setup** (ROADMAP §9): at T-60 min, open a New Book to warm up Orbis (it takes minutes). At T-15 min, do a rehearsal pass. Use headphones so the animation's sound doesn't reach the mic, and a wired connection or a hotspot. The demo runs in the **iPhone Duo simulator on a Mac**. The hinge comes from the simulator's fold controls, or from the in-app hinge slider if the simulator only gives set postures (TN-008). Voice goes into the Mac mic. A kid profile for "Maya" (loves dinosaurs) is set up in advance.

| Time | On screen | Say | Capture |
|---|---|---|---|
| 0:00–0:15 | Bookshelf, phone fully open | "Every parent has a lesson they're trying to teach. Every kid has a thing they're obsessed with. Pop! puts the two together." | 📸 **S1** bookshelf |
| 0:15–0:30 | New Book → the brief. Maya's profile already says *dinosaurs*. Lesson: **sharing** (a curated pack) | "Maya loves dinosaurs. This week we're working on sharing. That's the whole setup." | 📸 **S2** story brief |
| 0:30–1:00 | **Parent (voice):** *"Rex the dinosaur had the biggest pile of toys in the whole valley."* Text on the left → "painting…" → still → it moves | "I just talk. The words are cleaned up for a four-year-old. Now the picture… and now it's alive. The animation only shows what the page says." | 🎥 **R1** hero clip: voice → text → still → animation. Overlay the real timings once measured (TBD, Phase 2 and 3) |
| 1:00–1:20 | **Parent (typed):** *"Add a little dinosaur who wants to play."* Then a tap on **You continue** writes the next page, moving the sharing lesson along | "I can type too, and direct it. Or I just say 'you continue' and it writes the next page, keeping the lesson on track without lecturing." | 🎥 **R2** direction + You continue |
| 1:20–1:45 | Fold slowly: the page lifts and curls. Release early and it falls back. Fold past the threshold and it turns. The new page starts its own animation | "The hinge *is* the page. Let go and it falls back. Push past and it turns." | 🎥 **R3** curl following the hinge |
| 1:45–2:10 | Keep folding to ~90°: Rex and the little dinosaur rise out of the spine. Open flat: they fold back | "And like any good pop-up book…" *(pause and let it land)* | 🎥 **R4** pop-up · 📸 **S3** deck cover still |
| 2:10–2:30 | Close → the cover: *"Rex Learns to Share, a story for Maya"*. It lands on the shelf | "Close it and it's saved. Made at lunch; ready for bedtime." | 📸 **S4** cover screen |
| 2:30–2:50 | Hit **KILL** on the debug overlay (no live video anymore), then open the saved book from the shelf. Same text, same pictures, same animations; curl and pop-up still work | "Tonight, Maya sees exactly what I made. Nothing is generated again, so showing it costs nothing and works offline." | 🎥 **R5** exact replay with Reactor off |
| 2:50–3:00 | The spread, with Rex on the page | "The only screen time that happens with your kid, not instead of them." | — |

**Swap-ins:**
- *Made together (live with a child):* in place of the 1:00–1:20 beat, flip to **kid's turn**. The kid says *"And the little one had a purple tail!"* and it lands on the page (🎥 **R6**).
- *Apple audience:* in the 2:30 beat, also show the hinge status and angle on the overlay (📸 **S5**), and say that replay reads from the on-device copy.

**If something breaks** (ROADMAP §9, PRD §9):
- *Reactor fails:* the still-image pan-and-zoom takes over automatically. Keep talking: "the illustrator is still painting."
- *Network fails:* open the **saved golden book** (stored on the device), which replays exactly.
- *Speech fails:* type instead (typing is a first-class input), or fall back to Apple on-device speech.
- *Simulator hinge is jumpy:* switch to the in-app hinge slider.

### Media shot list (capture when each piece is built)

| ID | What | Available from | Where it goes |
|---|---|---|---|
| S1 | Bookshelf of saved covers | Phase 5 | §2; deck opener |
| S2 | Story brief: interests + lesson | Phase 2 | §5 "Who does what"; VC "Who pays" |
| R1 | Voice → text → still → animation in one take, with timings | Phase 3 | §6 hero clip; top of the VC deck |
| R2 | A typed direction, then "You continue" | Phase 2 | §5 "The parent's tools" |
| R3 | Curl following the hinge, falling back and committing | Phase 1 | §5 "Fold to turn"; Apple section |
| R4 / S3 | Pop-up at ~90° | Phase 4 | §5; deck cover |
| S4 | Cover on the closed screen, "a story for Maya" | Phase 5 | §5 "Close to save" |
| R5 | Saved book replaying exactly with Reactor killed (and ideally the network off) | Phase 5 | §6; VC unit economics; Apple section |
| R6 | Kid's turn during a made-together book | Phase 2 | §5 "One way to make a book" |
| S5 | Debug overlay: hinge angle, chunk, credit meter | Phase 3 | §8 Apple section |
| R7 | Kill Reactor mid-creation → still-pan, no error shown | Phase 3 | §9 "What if the video service goes down?" |

---

## 7. For VCs

### Market

- **Buyer, author and account owner:** parents of 3–8 year olds who want to teach their kids something. **Audience and co-creator:** the kid. **Not for:** kids alone, classrooms, kids over ~9, or anyone who wants a generic book without choosing what goes in it.
- **Wedge:** iPhone Duo owners with young kids, where the fold interactions are the hero.
- **Expansion:** every iPhone via the single-page reader (PRD H5), then iPad and Android (out of scope for now).
- **Size: TBD.** Method: households with a child aged 3–8 on a Duo (then any iPhone) × share of parents who make a book in a month × conversion to Pro × price. Fill this in only with sourced numbers.

### Who pays, and why

**The parent, who is also the author.** Pop! does a job the parent already has: *teach my kid this, in a way they'll actually listen to*. The parent sets up every book, shapes it, decides when it's done, and reads it with their child. The kid never sees purchases, settings or sharing; all three sit behind a parental gate (K4).

### Business model

- **3 free books, then Pro** (K5). **Depends on P-02 / D5.** The Pro price is **TBD**, set after measuring the real cost per book (D5). Whether Pro stays "unlimited" is Brian's call (P-02, proposed).
- Possible add-ons (printed book, gifting, lesson packs from partners) are in the [Ideas inbox](#10-ideas-inbox). They're not in the plan.

### Unit economics (honest version)

The biggest cost is live animation while a book is **being made**. Orbis Stable is billed per second at **$0.582 a minute** (TN-012). **Showing a saved book costs $0 in Orbis time**, because each page's clip is recorded while the book is made and replayed from storage (S13, D4 resolved).

| Live animation while making a book | Orbis Stable ($0.582/min) | Orbis Dynamic ($1.254/min) |
|---|---|---|
| 5 min | $2.91 | $6.27 |
| 10 min | $5.82 | $12.54 |
| **15 min (the PRD's planning case)** | **$8.73 ≈ $9** | $18.81 |

**Not in that number yet:**
- **Warm-up.** A session takes minutes to start, and we don't know yet whether billing starts at connection or at generation. If it's at connection, each warm-up minute adds $0.58. TBD (measured in Phase 0.3).
- **Everything else per book:** Gemini illustrations, layers and cover; OpenAI transcription, story model, moderation, lesson fact-checks and narration; Supabase storage for clips. TBD (measured in Phase 2 and 5).
- **The App Store commission** on Pro revenue.

**What that means, unmitigated:**
- Three free books can cost **~$26** in animation alone (3 × $8.73) for each family that makes all three, before we earn anything.
- A parent making one book a week (four a month) costs **~$35 a month** in animation alone (4 × $8.73). Pro as "unlimited" can't carry that without the mitigations below, which is why P-02 asks whether to keep "unlimited".
- **The good news:** each book is paid for once. Every bedtime replay after that is free.

**Mitigations:**
1. **Make once, show for free** *(built in: S13)*. Saved books replay recorded clips with no generation calls. *Risk:* recording clips from the in-app web view is unproven until Phase 0.3. The fallback is to re-animate live from the same picture and prompt, which isn't free and isn't exact.
2. **Only pay for what's on screen.** Use one session per book. Only animate the page that's open. Close idle sessions on purpose. The server cleans up stray sessions, because a failed connect can leave one billing (TN-011).
3. **Stable, not Dynamic:** under half the price per minute (D3).
4. **Stop streaming once the clip is saved** *(proposal)*: once a page's clip (length set at G0) is recorded, loop the clip instead of streaming live. The cost then tracks roughly *pages × clip length*, not how long the parent lingers.
5. **Tiered free books** *(proposal)*: free books use the still-image pan (the existing fallback) on most pages and live animation on the first page.
6. **Price Pro on measured cost** (*depends on P-02 / D5*). A fair-use allowance may beat "unlimited". PRD K5 still says unlimited, and the change is logged as P-02 (proposed) for Brian to decide.
7. **Prices may fall.** Per-minute prices for generative video may drop over time. We don't bank on it.

**North-star cost metric:** cost per finished book, TBD (measured after Phase 5). It's already a tracked product metric (PRD §5).

### Moat (honest: early)

We rent the models, and anyone can call them. What we can defend is what we build around them:
1. **Books made for *my* kid.** Every saved book is about this child's name and interests, and plays back exactly. The family shelf grows with each one.
2. **The lesson engine.** Curated lesson packs, fact-checking, and stories that move a lesson forward without lecturing, checked against a 10-brief accuracy set.
3. **Craft on a new form factor.** Curl, pop-up and close-to-save tuned to the Duo's hinge. It's easy to copy badly and hard to copy well.
4. **The page pipeline.** Page-anchored motion prompts, a drift guard, consistent characters, the next page prepared early, a safety gate at every step, and a 30-session red-team set.
5. **Trust with parents.** The parent sees every page first, calm defaults, no dark patterns, and we don't keep voices.

**What we don't claim:** a data moat. We deliberately don't keep audio.

### Risks (the ones an investor will ask about; full list in PRD §12)

| Risk | Why it matters | What we do |
|---|---|---|
| Cost per book (~$9 unmitigated) | Unit economics | Showing is free; the mitigations above; price after measuring (depends on P-02 / D5) |
| Clips can't be recorded from the web view | Exact replay and free showing | Phase 0.3 tries in-page recording first, then native capture of the web view. Last resort: still plus live re-animation (not exact) |
| A lesson teaches something wrong | Parents' trust | Curated lesson packs first, a fact-check for anything else, and in books made ahead the parent sees every page first |
| Orbis warps faces or drifts off the page | The magic breaks | Gentle motion, locked camera, drift guard. Fallback: animate only the background and keep the characters as crisp cutouts |
| Orbis takes minutes to warm up | The parent waits | Warm up when the book starts; show text and stills first |
| One live-video vendor | An outage or a price change | Orbis is one implementation of `LiveScene`; still-pan and clip replay don't need it (TN-009) |
| Kids' privacy law (COPPA) | Blocks release | Transcribe and discard audio, first name and interests only, parental gate. **Legal review before any public release** |
| Unsafe output reaches a child | Ends trust | Moderation on text, prompts and images; a frame tripwire; the parent previews books made ahead. Gate: 0 unsafe outputs in the red-team set |
| Small Duo install base | Wedge size | Also runs on every iPhone as a single-page reader |
| Demand is unvalidated | The whole thesis | Parent interviews and observed sessions (PRD §2) |

### The ask

*Placeholder, to be filled in from one source of truth that Brian owns.*
- **Raise:** TBD · **Instrument:** TBD
- **Use of funds:** TBD
- **Milestones it buys:** TBD. For reference, the build plan is about 78 focused hours to the MVP line and about 118 hours for the full scope (ROADMAP v2).
- **Team:** two engineers (Brian plus a teammate); bios TBD

---

## 8. For Apple engineers

### Using the iOS 27.1 Duo APIs the way they're meant to be used

1. **The hinge drives effects, never layout.** `onHingeChange(isEnabled:_:)` delivers the old and new `DeviceHingeContext`. `hinge.angle` feeds a pure, unit-tested `PostureMachine` whose only outputs are effects: curl progress, turn committed or cancelled, and pop depth. Layout follows only `hinge.status` (`.closed` → cover, open → spread) and user toggles. Apple's header says angle update rate and granularity are system policy and may change, and to "prefer `status` over the angle" when that's enough (TN-003). So the tests include sparse, irregular and jumpy angle sequences, and the curl smooths between samples.
   - A nil `hinge` means a device without a hinge, so the app shows the swipe reader (H5). `HingeSource` has three versions: Duo, debug slider, and none.
   - `DeviceHinge.Status` is a struct with static values, not an enum, so our `switch` has a `default` branch (TN-002).
2. **`ArrangementView` for the spread.** `ArrangementView { TextPage() } secondary: { ArtPage() }` with `.arrangementViewStyle(.split)` and `.splitArrangementLayoutRatio(_:)` (TN-004). The system owns the split; we don't hand-roll a two-pane layout.
3. **`reservedRegions` keep text and faces out of the fold and camera.** `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` with `.division` (fold) and `.occlusion` (camera) (TN-005). Text is padded by each region's `margins`. Art is generated at 16:9 with the important content in the centre, then cropped so faces stay clear. *What each kind marks is inferred from the names and gets confirmed in the Phase 0.2 overlay probe.*
4. **Closing is a verb.** `.closed` finishes and saves the book and shows its cover. The SDK has no cover-display API, so we assume the app runs on the outer screen (TN-007). How the simulator presents this is checked in Phase 0.1.
5. **Live video in a native app, recorded for exact replay.** Reactor has no Swift SDK, so its JS SDK is bundled (never loaded from the web) into a `WKWebView` behind a Swift `LiveScene` protocol (TN-009). The protocol has three implementations: `ReactorWebScene` (live, and records each page's clip), `StillPanScene` (fallback) and `ClipReplayScene` (plays saved clips). A saved book is kept on the device and shows with no network (TN-024).
6. **Pop-up without the Neural Engine.** Vision's foreground mask reportedly doesn't run in the Simulator (TN-014). So we generate the layers directly (a plate plus cutouts, keyed out with Core Image) and render them with SwiftUI 3D transforms. The layers exist before the flip, which is how we aim to have them rising within 300 ms of the pop angle (target; TBD, measured in Phase 4).
7. **Read-along timing on-device.** OpenAI text-to-speech has no word timings, so highlighting uses `AVSpeechSynthesizerDelegate`'s `willSpeakRangeOfSpeechString` callback (TN-015).

### Privacy by design

- **Audio** is streamed for transcription and never stored.
- **The only personal data** is the kid's first name and the interests the parent enters.
- **What's saved:** book text, pictures, pop-up layers and each page's animation clip, with a copy on the device.
- **Keys** stay on the server (Supabase Edge Functions and secrets). The app only receives short-lived tokens: an OpenAI Realtime client secret and a Reactor token, both minted server-side (TN-016, TN-011, TN-017).
- **Parent preview:** in a book made ahead, the parent sees every page before the child does (K1).
- **Monitoring** reports crashes and performance with personal data scrubbed (K6).
- **Parental gate** before settings, purchases and sharing (K4).
- **Not a Kids Category app** (D6, recommended): the parent is the author, the user and the account owner. This gets revisited before any public release.

### Built and demoed in the simulator only

- There's no physical Duo. The build uses Xcode 27.1 beta (27A9269), the iOS 27.1 simulator and the iPhone Duo device (TN-001).
- The mic is the Mac's. There's no camera, haptics or motion sensors. Pictures come in only through finger drawing or the photo picker.
- Whether the simulator delivers a continuous hinge angle is unverified until Phase 0.1. The fallback is an in-app hinge slider that drives the same `PostureMachine` (TN-008).
- Beta Xcode builds can't be submitted to the App Store.

---

## 9. Tough questions

| Question | Answer |
|---|---|
| **"Isn't this just more screen time?"** | It's made by the parent, for their child, and read together. Every book has a purpose the parent chose. We measure books shown to the child and reread, not minutes on screen. |
| **"Why would a parent make a book instead of buying one?"** | No bookstore has "a dinosaur story that teaches Maya to share". Parents know what their kid loves and what they need to learn; Pop! turns that into a book in minutes. *Hypothesis:* testing it is the first job of the parent interviews. |
| **"Isn't the parent doing all the work?"** | As much or as little as they want. They can narrate every page, give a direction or two, or tap "You continue" and let the AI write it, keeping the lesson on track. |
| **"What if the lesson is wrong?"** | Lessons start from curated lesson packs, and anything else goes through a fact-check. In a book made ahead, the parent sees every page before the child does. We also check 10 lesson briefs for accuracy before every demo. |
| **"$9 of video per book. How is this a business?"** | $9 is the unmitigated cost of 15 live minutes while *making* a book. Showing it is free forever after, because the clips are recorded. On top of that: animate only the open page, stop streaming once a page's clip is saved (proposal), and use Stable. Pro is priced on the measured cost; whether it stays unlimited is open (P-02 / D5). |
| **"What stops OpenAI, Google or Apple from doing this?"** | Nothing stops them from building a story generator. What's hard is a book about *this* child that teaches *this* lesson well, the fold interactions, and safety a parent trusts. Big platforms build general tools; we build one narrow thing very well. Early on, speed and craft are the moat. |
| **"Is it safe for a four-year-old?"** | Every page's text, art prompt, animation prompt and picture passes a kid-safe check before a child sees it, and in a book made ahead the parent previews every page. Sampled frames act as a tripwire back to the still. Our gate is 0 unsafe outputs in the red-team set. |
| **"You're recording kids' voices?"** | No. Audio is streamed for transcription and discarded. We keep a first name and the interests the parent enters, nothing else personal. There's a legal (COPPA) review before any public release. |
| **"Have you tested with parents and kids?"** | Not yet. Next come 5–10 parent interviews and observed sessions that measure time on task, pages per book and what the child remembers. |
| **"Why the Duo? Hardly anyone has one."** | The Duo is where the magic is, and that's our wedge, not our ceiling. The whole app also runs on any iPhone as a single-page reader. |
| **"Why live video instead of pre-rendered clips?"** | While the parent is making the book, pages change with every direction. With a warm session, a new page is a `reset` plus a new image, not a render job. Time to first frame is TBD (measured in Phase 0.3). Once the book is saved, it *is* pre-rendered: each page replays its recorded clip. |
| **"What if the video service goes down?"** | While making: the still picture with a slow pan-and-zoom takes over automatically, and nobody sees an error. Saved books don't need it at all. |
| **"Does the animation go off-script?"** | The prompt is built only from this page's text and picture, with a locked camera, one gentle motion, and "nothing new enters the scene". A drift guard re-anchors it. Drift at 30 s and 60 s is measured in Phase 0.3. |
| **"How fast is it?"** | Targets (p50): page text ≤ 2.5 s after the sentence ends or a "You continue" tap; text plus placeholder ≤ 5 s; still ≤ 10 s; animation ≤ 5 s after a flip. Measured numbers: TBD (Phase 2 and 3). |
| *Apple:* **"Why doesn't the angle drive layout?"** | Your header says angle updates are system policy and can change rate and precision. Layout tied to the angle would jitter. `status` drives layout, and the angle drives effects only. |
| *Apple:* **"Why not the Kids Category?"** | The parent is the author and the account owner, and the kid is the audience. The Kids Category also restricts third-party analytics such as Sentry. It's an open decision (D6), revisited before any public release. |
| *Apple:* **"A web view inside a native app?"** | Reactor ships no Swift SDK. The JS is bundled, never loaded remotely, and sits behind a Swift protocol, so it can be swapped for native WebRTC later. Saved books replay natively from recorded clips. |
| *Apple:* **"Did you run it on a real Duo?"** | No, only in the simulator. The hinge comes from the simulator's controls or an in-app slider. We don't use haptics or motion sensors. |

---

## 10. Ideas inbox

New pitch angles go here. Status: **new** · **used** (moved into the pitch) · **parked** · **depends on P-NN** (waiting on a proposed pivot). Ideas that would change product scope go to the **Pop! · Pivots & Ideas** session, not here.

| Date | Idea | Audience | Status |
|---|---|---|---|
| 2026-09-25 | **Parent-first framing: "a parent makes a lesson book in minutes."** | Both | **used**: P-01 accepted 2026-09-25; the whole pitch is re-framed. The "2 minutes" version needs a measured time first: TBD (Phase 2) |
| 2026-09-25 | **Category framing: learning through the kid's own interests.** For VCs who bucket by category, Pop! is edtech where the lesson rides inside a story about what this child loves, authored by the parent (from Pivots & Ideas) | VC | used (§7 "Who pays, and why"); lead with it for edtech-focused investors |
| 2026-09-25 | **"Made at lunch, ready for bedtime."** The made-ahead flow as a one-line hook | VC | used (§6, 2:10 beat) |
| 2026-09-25 | **Cost as a feature:** clips are recorded once, so showing a book is instant, free and works offline | Both | used (§7 unit economics, §6 2:30 beat) |
| 2026-09-25 | **"Unlimited rereads of every book you make."** The Pro line if Pro becomes a monthly allowance of new books, while showing saved books stays unlimited | VC | **depends on P-02** (proposed) |
| 2026-09-25 | **Lesson packs from partners:** pediatric dentists, child therapists or schools supply curated lesson packs for real moments (a B2B2C angle) | VC | new; would need a Pivots review |
| 2026-09-25 | **Printed hardcover** of a saved book as an upsell beyond Pro (PDF export, B3, is the base) | VC | new |
| 2026-09-25 | **Grandparent gifting:** a grandparent makes a book for a grandchild, or it's shared as a video (B4) | VC | new; remote co-creation is out of scope today |
| 2026-09-25 | **"The fold as a storytelling device":** posture is a story mechanic (close = save), not a UI split. A strong angle for an Apple design or developer talk | Apple | new |
| 2026-09-25 | **Bilingual books:** the story language is already in the data model | VC | new |
