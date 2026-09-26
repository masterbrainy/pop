# Pop! — Product Requirements Document

*Status: DRAFT v1 · 2026-09-25 · Owner: Brian Huang · Companion doc: [ROADMAP.md](ROADMAP.md)*

> **"The only screen time that happens with your kid, not instead of them."**

Pop! is a picture book that a parent and child make together, live, about anything. The kid tells a story out loud and the iPhone Duo turns into a book that writes and illustrates itself. Each page's picture comes alive as a short animation. Fold the phone to turn the page, tilt it to about 90° and the scene pops up out of the spine, and close it to finish the book.

---

## 1. Problem

Parents of 3–8 year olds want screen time that builds connection and imagination. Most kids' apps are designed for one child alone and compete with the parent for attention. Making up a story at bedtime is the opposite: it's shared and creative. But it leaves nothing behind, and a tired parent often runs out of ideas. Nothing today turns a child's spoken story into a finished, illustrated book as they speak it, with the parent in the loop.

## 2. Evidence

- Assumption: parents will prefer a co-created story app over solo kids' apps. *Needs validation through 5–10 parent interviews and a prototype session with a real child.*
- Assumption: seeing their words become pictures within seconds keeps a 3–8 year old engaged for a 5–10 page story. *Needs validation through observed prototype sessions (time on task, pages per book).*
- No user research, analytics or quotes have been supplied yet. Every "why" in this doc is a hypothesis.

## 3. Users

| | Who | Context |
|---|---|---|
| **Primary: Parent** | Owns the phone and the account. Sets mode, reading level and filters. Reads alongside the child. | Bedtime, waiting rooms, weekend mornings, or preparing a child for a real event. |
| **Co-creator: Kid (3–8)** | Tells the story out loud. Taps, draws and listens. Never manages settings, purchases or sharing. | Sits next to the parent. May not read yet. |
| **Not for** | Kids using the app alone, classrooms, kids over ~9, or anyone who wants a finished book without taking part. | — |

## 4. Hypothesis

We believe **a book that writes, illustrates and animates itself as a child speaks, and that responds to the fold of the phone**, will turn screen time into **shared creative time** for **parents of 3–8 year olds**.
We'll know we're right when **families finish books** (at least 5 pages) **and come back to make another within a week**.

## 5. Success metrics

**Demo and MVP gates.** These are measurable now.

| Metric | Target | How measured |
|---|---|---|
| End-to-end reliability | 5 rehearsal runs in a row of a 5-page book, with no crash and no manual fix | Rehearsal log |
| Sentence end → page text visible | p50 ≤ 2.5 s | Timing spans per pipeline stage (Sentry) |
| Sentence end → page visible (text plus "painting…" art placeholder) | p50 ≤ 5 s (the spec's target) | Same |
| Page art visible (still illustration) | p50 ≤ 10 s after the page's text *(TBD, measured in the Phase 0 spike)* | Same |
| Page flip → animation playing | p50 ≤ 5 s (the still is shown until then) | Same |
| Unsafe output shown to the child | 0 in a 30-transcript red-team set | Eval script |
| Page curl tracks the hinge | No visible lag when driven by the simulator's hinge controls | Manual check with screen recording |
| Pop-up response | Layers start rising ≤ 300 ms after the pop angle is reached | Timing span |

**Product metrics after the demo.** *Targets are TBD until we have analytics baselines.*
Books finished per active family per week · share of sessions reaching 5 or more pages · share of books reread · conversion from free to Pro after the 3rd book · cost per finished book.

## 6. Product principles

1. **Together, not instead.** Every screen assumes two people. The parent's controls never interrupt the child's flow.
2. **The kid leads, the AI keeps it together.** The AI never overrides the child's idea. It only makes it coherent, safe and readable.
3. **Calm and safe by default.** Nothing scary, no dark patterns, no error codes. A failure always looks like "the illustrator is still painting…".
4. **The hinge is for magic, not navigation.** Hinge angle drives effects (curl, pop-up). Layout comes from the posture and user toggles, never from the angle. This follows Apple's guidance.
5. **The page stays on topic.** Each page's picture and animation show only what that page's text says.

## 7. The core experience

1. **Parent starts a book.** They choose a mode (Imagine, Learn or Real life), plus a topic or a real moment if needed. The kid's first name and reading level come from the parent profile. The live animation engine starts warming up now, because it takes minutes to be ready.
2. **The kid tells the story.** A "kid's turn / parent's turn" toggle tells the story engine who is speaking. Rambling speech becomes clean page text at the right reading level, and the engine decides where each page ends.
3. **The page fills in**, left to right:
   - **Left page:** the story text appears first.
   - **Right page:** a "painting…" placeholder, then the finished illustration, then the illustration **comes alive as a short animation**. The animation shows only this page's scene.
4. **The kid changes their mind** ("no, it was a dragon!"). The current page regenerates: new text, new picture, new animation.
5. **Fold to turn.** The page lifts and curls with the hinge. Let go early and it falls back; push past the threshold and it turns. **Each newly shown page starts its own fresh animation.**
6. **Tilt to about 90° to pop up.** The page's characters rise out of the spine in front of the background, deeper as the angle grows. Opening flat folds them back into the picture and the animation resumes.
7. **Close to finish.** The cover screen shows AI cover art and a title such as *"The Turtle Who Flew, by Maya."* The book joins the bookshelf.

## 8. Functional requirements

Priority: **P0** = must-have for the demo · **P1** = core product · **P2** = cut-list features, in the order they would be cut last · **P3** = stretch.

### 8.1 Story creation

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| S1 | Live voice storytelling with streaming speech-to-text | P0 | The kid speaks and the text for the current page appears within the latency budget |
| S2 | Kid's turn / parent's turn toggle | P0 | Parent speech is treated as guidance, not story text, unless the parent explicitly narrates |
| S3 | Story engine: clean text at the chosen reading level, page breaks, a running story bible | P0 | Text meets the per-level word limits (§8.7). Characters and setting stay consistent across pages |
| S4 | Consistent characters in the art | P0 | Each character keeps a fixed reference description and reference image, used for every picture |
| S5 | Live branching: the current page regenerates when the kid changes their mind | P1 | Revised text within ≤ 3 s. Art and animation restart. Superseded work is cancelled |
| S6 | Imagine mode | P0 | Anything goes; the AI keeps the story coherent |
| S7 | Learn mode | P1 | Parent picks a topic. Each page contains 1–2 verified facts and a highlighted "word of the story". The book ends with 3 "remember when" questions in the story's voice |
| S8 | Real-life mode | P1 | Parent describes a moment (first day of school, new sibling, dentist). The tone stays calm and hopeful and the story ends reassuringly |
| S9 | Next page prepared early | P0 | While the kid tells page N+1, page N's art and animation prompt are finished. A flip never waits on text or art that could have been ready |

### 8.2 The page (book mode, fully open)

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| P1 | Left page: story text at the kid's reading level | P0 | Large, legible type. Kept out of the fold and camera regions |
| P2 | Right page: page illustration in one fixed art style | P0 | Style is consistent across the book. Faces are kept out of the fold and camera regions |
| P3 | **Living illustration:** the right page's picture animates using Reactor's Orbis model (image-to-video anchored on the page's illustration) | P0 | Animation starts ≤ 5 s after the page is shown. The still shows until the first frames arrive |
| P4 | **Animation stays relevant:** motion shows only what this page's text and picture contain | P0 | The animation prompt comes only from this page's text and picture. The camera and scene stay fixed. Motion is gentle. Nothing new appears. A drift guard re-anchors the animation to the still if it wanders |
| P5 | **New page, new animation:** every flip starts a fresh animation for the page now showing | P0 | A flip ends the previous page's animation; the new one begins from the new page's picture |
| P6 | Graceful fallback when the animation service is down | P0 | The right page shows the still with a slow pan-and-zoom. The child never sees an error |

### 8.3 Posture interactions (iPhone Duo)

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| H1 | Page curl follows the real hinge angle; falls back if released early, turns past the threshold | P0 | Driven by the simulator's hinge controls; tracks without visible lag |
| H2 | Pop-up at about 90°: characters rise from the spine in front of the background; depth grows with the angle; opening flat folds them back | P0 | Works on every generated page in the Duo simulator |
| H3 | Closed = finish the book, with cover art and a "Title, by {Name}" cover | P1 | Closing a book with at least 1 page finishes it and shows the cover on the closed-phone screen |
| H4 | The hinge drives effects only, never layout | P0 | Layout depends only on posture and user toggles |
| H5 | Non-Duo iPhones: single-page reader with swipe turns | P1 | The whole app works on a standard iPhone simulator |

### 8.4 Bookshelf and sharing

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| B1 | Bookshelf of finished books shown as covers | P1 | Tapping a cover opens the book for rereading |
| B2 | Reread | P1 | Pages show text and art. Animations replay (from saved clips if recording ships, otherwise live) |
| B3 | Share as PDF | P1 | The parent exports the book as a PDF from behind a parental gate |
| B4 | Share as video | P2 | Page animations stitched together with narration |

### 8.5 Cut-list features (kept in this order; talking characters is cut first)

| ID | Requirement | Pri |
|---|---|---|
| C1 | Read-along: narration with word-by-word highlighting | P2 (kept longest) |
| C2 | Kid's drawing as the hero: the kid finger-draws a character that stars in the book | P2 |
| C3 | Reading together: on the parent's half, a co-pilot strip with the next question to ask, a fact card (Learn) and the word of the story | P2 |
| C4 | Talking characters: tap a character to hear its line in its own voice | P3 (cut first) |

### 8.6 Parent controls, safety and business

| ID | Requirement | Pri |
|---|---|---|
| K1 | Every page's text, art prompt, animation prompt and generated picture passes a kid-safe check before the child sees it | P0 |
| K2 | Learn-mode facts come from curated fact packs or pass a separate fact-check | P1 |
| K3 | Parent settings: content filters, topics to avoid, reading level, story language | P1 |
| K4 | Parental gate before settings, purchases and sharing | P1 |
| K5 | Paywall: 3 free books, Pro for unlimited | P1 |
| K6 | Crash and performance monitoring without personal data | P1 |

### 8.7 Reading levels (proposed defaults)

| Level | Ages | Per page |
|---|---|---|
| Listener | 3–4 | 1–2 short sentences, ≤ 15 words, very simple vocabulary |
| Early reader | 5–6 | 2–3 sentences, ≤ 30 words |
| Reader | 7–8 | Up to 5 sentences, ≤ 60 words |

## 9. Non-functional requirements

- **Latency:** see the budget in §5. The spec's "under 5 s" target is met by the page text plus a placeholder. The illustration and animation arrive after that (decision D2).
- **Privacy:** audio is streamed for transcription and never stored. The only personal data is the kid's first name. What is saved: book text, pictures, and (if that feature ships) animation clips. API keys stay on the server. The app only receives short-lived tokens.
- **Cost awareness:** the live animation is billed per second, about $0.58 per minute on Orbis Stable. The session must be warmed and shut down on purpose, and stray sessions must be cleaned up by the server.
- **Reliability:** every external service has a child-safe fallback: Apple on-device speech recognition, the still-image pan, a gentle "let's try that again" line, or a placeholder.
- **Accessibility:** large tap targets for small hands, Dynamic Type on the parent's screens, captions via read-along.
- **Build environment:** built and demoed only on the iPhone Duo simulator in Xcode 27.1 beta. Mic input comes from the Mac. No camera, haptics or motion sensors. Pictures come in only through finger drawing or the photo picker.

## 10. Scope

**MVP (the demo):** Imagine mode · live voice → text → art → animation per page · fold-to-turn curl · pop-up · closing to finish, with a cover · non-Duo fallback for development.

**Out of scope for now**
- Physical iPhone Duo, haptics, motion sensors, camera input: the build and demo are simulator-only.
- iPad, Android, web.
- Multiple kid profiles and co-creation with a relative in another place.
- Offline generation.
- Languages other than English at the demo. The language setting is in the data model; other languages are untested.
- App Store submission: beta Xcode builds can't be submitted.

## 11. Assumptions and constraints

- **Duo APIs.** The iOS 27.1 SDK in Xcode 27.1 beta (27A9269) was checked on 2026-09-25 and contains the hinge API (status plus a continuous angle), the two-pane `ArrangementView`, and reserved regions for the fold and camera. There is **no dedicated cover-display API**, so the closed posture is assumed to run the app on the outer screen. Still unverified until the Phase 0 probe: whether the *simulator* delivers a continuous angle, and how it presents the closed/cover screen. An in-app hinge slider is the fallback for development and the demo.
- **Vendors:** Reactor (Orbis) for animation · Google Gemini for illustrations, layer images and animation prompts · OpenAI for speech-to-text, the story model, moderation and narration · Supabase for storage and the server functions that hold the keys · Sentry · RevenueCat. *Gemini covering images only is an assumption (decision D7).*
- The Orbis integration builds on a teammate's hackathon starter, used with permission (see the roadmap's reuse table).

## 12. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Orbis animation warps characters' faces or drifts off the page's content | Med | High | Motion prompts ask for gentle motion and a locked camera. Drift guard re-anchors. Phase 0 spike compares Orbis Stable and Dynamic. Fallback: animate only the background and keep characters as crisp cutouts |
| Orbis takes minutes to warm up | High | Med | Warm when the book starts (demo: well before going on stage). Show stills until ready |
| Cost per book (~$9 of Orbis time for a 15-minute session) | High | High (unit economics) | Record clips so rereads are free. Close idle sessions. Price Pro accordingly (decision D5) |
| The simulator's hinge controls give only set postures, not a continuous angle | Med | High (curl and pop-up) | Phase 0 probe. In-app hinge slider as fallback |
| Folding to turn and folding to about 90° to pop up are the same motion | High | Med | Pick one gesture model in Phase 0 (decision D1) |
| Apple's Vision background removal doesn't run in the simulator (reportedly needs the Neural Engine) | High | High (pop-up) | Generate pop-up layers directly (background plate plus character cutouts). No segmentation needed |
| Art or animation latency misses the 5 s target | High | Med | Show text first, then a placeholder, then the still, then the animation. Prepare the next page early. Measure in Phase 0 |
| An unsafe picture or animation reaches a child | Low | Critical | Moderate before display. Animation prompts are generated only from checked content. Sampled frames act as a tripwire and switch back to the still |
| The Orbis session drops mid-demo | Med | High | Reconnect with backoff. Server-side cleanup. Kill switch. Still-image fallback |
| Mic picks up app audio (the animation's generated sound, narration) | High | Med | Mute animation audio while the mic is live. Headphones for the demo |
| Privacy law for kids' voice data (COPPA) | Med | High | Transcribe and discard the audio, first name only, parental gate. **Legal review before any public release** |

## 13. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| D1 | Gesture model: how folding to turn and folding to pop up coexist | One continuous motion: folding past the turn threshold commits the page turn; keep folding to about 90° and the new page pops up; opening flat plays its animation |
| D2 | What "page appears in under 5 s" means | Text plus art placeholder within 5 s; still ≤ 10 s; animation ≤ 5 s after flip |
| D3 | Orbis Stable vs Dynamic | Stable (higher resolution, half the price); confirm in the Phase 0 spike |
| D4 | Record each page's animation clip for rereads and video export | Yes, if the Phase 0 spike shows recording works in the in-app web view |
| D5 | Pro pricing given Orbis cost | TBD after measuring the real cost per book |
| D6 | Kids Category listing (it restricts third-party analytics such as Sentry) | Not listed as a Kids Category app: the product is used by the parent |
| D7 | Gemini's role | Images and animation prompts only. OpenAI keeps speech, story and narration |
| D8 | Timeline and demo date | ✅ Resolved: no deadline. The full scope is built, including all cut-list features |

---
*Next step: [ROADMAP.md](ROADMAP.md) turns these requirements into phases, tasks and cut lines.*
