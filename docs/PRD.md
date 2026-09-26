# Pop! — Product Requirements Document

*Status: DRAFT v3 · 2026-09-26 · P-01 (parents drive creation; lessons optional) · P-02 superseded (everything is free) · Owner: Brian Huang · Companion doc: [ROADMAP.md](ROADMAP.md)*

**Pop! is a free, hackathon-style pitch and demo, not a release.** Nothing is sold. This document covers what makes the demo great, reliable and safe.

> **"The only screen time that happens with your kid, not instead of them."**

Pop! lets a parent make a picture book for their child, about whatever the child loves, and, if the parent likes, about something it should teach. The parent tells the story out loud or types it, and directs it as it goes ("add a friendly dragon", "make it about taking turns"). The iPhone Duo writes and illustrates each page as they go, and each page's picture comes alive as a short animation. The parent can make the book ahead of time, shape it until they're happy, save it, and later show it to their child exactly as it was made. Or they can make it live with the child watching and chiming in. **It's the same flow either way; the only difference is who's watching.** Fold the phone to turn the page, tilt it to about 90° and the scene pops up out of the spine, and close it to finish the book.

---

## 1. Problem

Parents of 3–8 year olds know their child best: what they love, what they're going through, and what they're curious about. They'd love a story made just for their child, whether it's about a dinosaur obsession, the family cat or the first day of school, or one that quietly teaches sharing. But making a good illustrated book takes skill and time they don't have. Made-up bedtime stories leave nothing behind, and a tired parent often runs out of ideas. Most kids' apps are built for one child alone and hand the parent a generic story. Nothing today lets a parent turn their idea into a finished, illustrated, animated book in minutes. That means a book the parent shapes as it's made, then reads with their child, or makes together with them.

## 2. Evidence

- Assumption: parents want to author books for their own child: to delight them, to prepare them for a real moment, or sometimes to teach something. *Needs validation through 5–10 parent interviews.*
- Assumption: a story about the child's own interests holds a 3–8 year old's attention better than a generic book. *Needs validation through observed sessions (time on task, pages per book, what the child remembers).*
- Assumption: seeing words become pictures within seconds keeps the parent, and a watching child, engaged for a 5–10 page book. *Needs validation through observed prototype sessions.*
- No user research, analytics or quotes have been supplied yet. Every "why" in this doc is a hypothesis.

## 3. Users

| | Who | Context |
|---|---|---|
| **Primary: Parent (the author)** | Makes the book: chooses what it's about (and, optionally, what it should teach), tells or types the story, directs changes, and decides when it's finished and saved. Owns the phone and the account. Sets reading level and filters. | Ahead of time (a lunch break, the evening before), or live with the child at bedtime, in a waiting room, or before a real event. |
| **Audience and co-creator: Kid (3–8)** | Sees the finished book, or watches it being made. Listens, reads along, and can add ideas on "kid's turn". Never manages settings or sharing. | Sits next to the parent. May not read yet. |
| **Not for** | Kids using the app alone, classrooms, kids over ~9, or anyone who wants a generic book without choosing what goes in it. | — |

## 4. Hypothesis

We believe **letting parents make a picture book about what their child loves, one that writes, illustrates and animates itself as they tell it and responds to the fold of the phone**, will turn screen time into **shared time** for **parents of 3–8 year olds and their kids**.
We'll know we're right when **parents in test sessions finish books** (at least 5 pages), **show them to their child, and want to make another**.

## 5. Success metrics

**Demo and MVP gates.** These are measurable now.

| Metric | Target | How measured |
|---|---|---|
| End-to-end reliability | 5 rehearsal runs in a row of a 5-page book, with no crash and no manual fix | Rehearsal log |
| Saved book replays exactly | Every page shows the same text, picture and animation clip as when it was made, with no generation calls | Automated replay check |
| Sentence end (or "You continue" tap) → page text visible | p50 ≤ 2.5 s | Timing spans per pipeline stage (local timing logs and the debug overlay) |
| Sentence end → page visible (text plus "painting…" art placeholder) | p50 ≤ 5 s (the spec's target) | Same |
| Page art visible (still illustration) | p50 ≤ 10 s after the page's text *(TBD, measured in the Phase 0 spike)* | Same |
| Page flip → animation playing | p50 ≤ 5 s (the still is shown until then) | Same |
| Unsafe output shown to the child | 0 in a 30-transcript red-team set | Eval script |
| Page curl tracks the hinge | No visible lag when driven by the simulator's hinge controls | Manual check with screen recording |
| Pop-up response | Layers start rising ≤ 300 ms after the pop angle is reached | Timing span |

## 6. Product principles

1. **Made by the parent, shared with the child.** Every book is meant to be read together. When the child is watching, the parent's controls never interrupt the child's flow.
2. **The parent drives, the AI keeps it together.** The parent directs the story, and the child can join in. The AI never overrides their ideas. It only makes them coherent, safe and readable. If the parent asks the story to teach something, it comes through the story, not a lecture.
3. **Calm and safe by default.** Nothing scary, no dark patterns, no error codes. A failure always looks like "the illustrator is still painting…".
4. **The hinge is for magic, not navigation.** Hinge angle drives effects (curl, pop-up). Layout comes from the posture and user toggles, never from the angle. This follows Apple's guidance.
5. **The page stays on topic.** Each page's picture and animation show only what that page's text says.
6. **What you save is what they see.** A saved book plays back exactly as it was made: the same text, pictures and animations.

## 7. The core experience

There is **one way to make a book**. The parent can do it alone ahead of time or with the child beside them; the steps are identical, and the only difference is who's watching.

1. **Parent starts a book** with a short story brief: what the child loves (from the kid profile, for example dinosaurs, trucks, their cat), an optional real moment (first day of school, a new sibling, the dentist), and an optional free-text field: "Anything you'd like this story to teach?" (for example sharing, or why we brush our teeth). The child's first name and reading level come from the kid profile. The live animation engine starts warming up now, because it takes minutes to be ready.
2. **The parent tells the story**, by voice or by typing. They can narrate a page themselves, give a direction ("add a friendly dragon", "she should learn to wait her turn"), or tap **"You continue"** so the AI writes the next page following the brief and every direction so far. Rambling speech becomes clean page text at the right reading level, and the engine decides where each page ends. If the child is there, a "parent's turn / kid's turn" toggle lets them add ideas the same way.
3. **The page fills in**, left to right:
   - **Left page:** the story text appears first.
   - **Right page:** a "painting…" placeholder, then the finished illustration, then the illustration **comes alive as a short animation**. The animation shows only this page's scene.
4. **Change anything** ("no, make it a dragon!"). The current page regenerates: new text, new picture, new animation. The change carries into the pages that follow.
5. **Fold to turn.** The page lifts and curls with the hinge. Let go early and it falls back; push past the threshold and it turns. **Each newly shown page starts its own fresh animation.**
6. **Tilt to about 90° to pop up.** The page's characters rise out of the spine in front of the background, deeper as the angle grows. Opening flat folds them back into the picture and the animation resumes.
7. **Finish and save.** When the parent is happy, closing the phone (or tapping Save) finishes the book. The cover screen shows AI cover art and a title such as *"Rex Learns to Share, a story for Maya."* The book is saved to the bookshelf exactly as it was made: text, pictures, pop-up layers and each page's recorded animation clip.
8. **Show it.** Opening a saved book plays it back exactly as it was made, with the same fold-to-turn and pop-up, and needs no new generation. A book made live with the child is saved and shown the same way.

## 8. Functional requirements

Priority: **P0** = must-have for the demo · **P1** = core product · **P2** = cut-list features, in the order they would be cut last · **P3** = stretch.

### 8.1 Story creation

*There are no separate modes. Everything goes through one story brief (S4). A parent who wants the story to teach something says so in the brief or in a direction; there's no lesson subsystem. S9 and S10 (lesson features) were removed on 2026-09-26.*

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| S1 | Live voice storytelling with streaming speech-to-text | P0 | The parent (or kid) speaks and the text for the current page appears within the latency budget |
| S2 | Typed input | P0 | Anything the parent could say, they can type. It goes through the same story engine |
| S3 | Parent's turn / kid's turn toggle | P0 | The parent is the default speaker. Parent input is either narration or a direction, and the engine tells them apart. On kid's turn, the child's words become story content, cleaned up |
| S4 | Kid profile and story brief | P0 | Kid profile: first name, reading level, things they love. Brief per book: which interests to use, an optional real moment, and an optional free-text "Anything you'd like this story to teach?". The engine follows the brief on every page |
| S5 | Story engine: clean text at the chosen reading level, page breaks, a running story bible | P0 | Text meets the per-level word limits (§8.7). Characters and setting stay consistent across pages |
| S6 | Consistent characters in the art | P0 | Each character keeps a fixed reference description and reference image, used for every picture |
| S7 | Directions and changes: the parent (or kid) says what to add or change | P0 | Revised page text within ≤ 3 s. Art and animation restart. Superseded work is cancelled. The direction carries into later pages |
| S8 | "You continue": the AI writes the next page | P0 | The page follows the brief and every direction so far, within the same latency budget |
| S11 | Real-moment tone | P1 | When the brief has a real moment, the tone stays calm and hopeful and the story ends reassuringly |
| S12 | Next page prepared early | P0 | While page N+1 is being told, page N's art and animation prompt are finished. A flip never waits on text or art that could have been ready |
| S13 | Save and show exactly | P0 | A saved book stores each page's text, picture, pop-up layers and recorded animation clip, and keeps a copy on the device. Showing it replays all of them unchanged, with no generation calls, and works without a network |

### 8.2 The page (book mode, fully open)

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| P1 | Left page: story text at the kid's reading level | P0 | Large, legible type. Kept out of the fold and camera regions |
| P2 | Right page: page illustration in one fixed art style | P0 | Style is consistent across the book. Faces are kept out of the fold and camera regions |
| P3 | **Living illustration:** the right page's picture animates using Reactor's Orbis model (image-to-video anchored on the page's illustration) | P0 | Animation starts ≤ 5 s after the page is shown. The still shows until the first frames arrive |
| P4 | **Animation stays relevant:** motion shows only what this page's text and picture contain | P0 | The animation prompt comes only from this page's text and picture. The camera and scene stay fixed. Motion is gentle. Nothing new appears. A drift guard re-anchors the animation to the still if it wanders |
| P5 | **New page, new animation:** every flip starts a fresh animation for the page now showing | P0 | A flip ends the previous page's animation; the new one begins from the new page's picture. In a saved book, the page's recorded clip plays instead (S13) |
| P6 | Graceful fallback when the animation service is down | P0 | The right page shows the still with a slow pan-and-zoom. The child never sees an error |

### 8.3 Posture interactions (iPhone Duo)

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| H1 | Page curl follows the real hinge angle; falls back if released early, turns past the threshold | P0 | Driven by the simulator's hinge controls; tracks without visible lag |
| H2 | Pop-up at about 90°: characters rise from the spine in front of the background; depth grows with the angle; opening flat folds them back | P0 | Works on every generated page in the Duo simulator |
| H3 | Closed = finish and save the book, with cover art and a "Title, a story for {Name}" cover | P1 | Closing a book with at least 1 page finishes and saves it and shows the cover on the closed-phone screen. A Save button does the same on any device |
| H4 | The hinge drives effects only, never layout | P0 | Layout depends only on posture and user toggles |
| H5 | Non-Duo iPhones: single-page reader with swipe turns | P1 | The whole app works on a standard iPhone simulator |

### 8.4 Bookshelf and sharing

| ID | Requirement | Pri | Acceptance criteria |
|---|---|---|---|
| B1 | Bookshelf of saved books shown as covers | P0 | Tapping a cover opens the book |
| B2 | Show a saved book | P0 | Pages show the saved text and art, and each page plays its recorded clip (S13). Curl and pop-up work as they did when it was made |
| B3 | Share as PDF | P1 | The parent exports the book as a PDF from behind a parental gate |
| B4 | Share as video | P2 | Recorded page clips stitched together with narration |

### 8.5 Cut-list features (kept in this order; talking characters is cut first)

| ID | Requirement | Pri |
|---|---|---|
| C1 | Read-along: narration with word-by-word highlighting | P2 (kept longest) |
| C2 | Kid's drawing as the hero: the kid finger-draws a character that stars in the book | P2 |
| C3 | Reading together: on the parent's half, a co-pilot strip with the next question to ask about the page | P2 |
| C4 | Talking characters: tap a character to hear its line in its own voice | P3 (cut first) |

### 8.6 Parent controls and safety

*K2 (lesson fact-checking) and K5 (paywall) were removed on 2026-09-26: there's no lesson subsystem, and everything is free.*

| ID | Requirement | Pri |
|---|---|---|
| K1 | Every page's text, art prompt, animation prompt and generated picture passes a kid-safe check before the child sees it. In a book made ahead of time, the parent also sees every page before the child does | P0 |
| K3 | Parent settings: content filters, topics to avoid, reading level, story language | P1 |
| K4 | Parental gate before settings and sharing | P1 |
| K6 | Local timing logs and the in-app debug overlay; no third-party crash or analytics service | P1 |

### 8.7 Reading levels (proposed defaults)

| Level | Ages | Per page |
|---|---|---|
| Listener | 3–4 | 1–2 short sentences, ≤ 15 words, very simple vocabulary |
| Early reader | 5–6 | 2–3 sentences, ≤ 30 words |
| Reader | 7–8 | Up to 5 sentences, ≤ 60 words |

## 9. Non-functional requirements

- **Latency:** see the budget in §5. The spec's "under 5 s" target is met by the page text plus a placeholder. The illustration and animation arrive after that (decision D2).
- **Privacy:** audio is streamed for transcription and never stored. The only personal data is the kid's first name and the interests the parent enters. What is saved: book text, pictures, pop-up layers and animation clips. API keys stay on the server. The app only receives short-lived tokens.
- **Demo Reactor credit budget:** live animation is billed per second, about $0.58 per minute on Orbis Stable (about $9 for 15 live minutes). It runs only while a book is being made; showing a saved book plays recorded clips and uses no credit. Budget enough credit for rehearsals plus the demo, watch the credit meter in the debug overlay, warm and shut down sessions on purpose, and have the server clean up stray sessions.
- **Reliability:** every external service has a child-safe fallback: Apple on-device speech recognition, the still-image pan, a gentle "let's try that again" line, or a placeholder.
- **Accessibility:** large tap targets for small hands, Dynamic Type on the parent's screens, captions via read-along.
- **Build environment:** built and demoed only on the iPhone Duo simulator in Xcode 27.1 beta. Mic input comes from the Mac. No camera, haptics or motion sensors. Pictures come in only through finger drawing or the photo picker.

## 10. Scope

**MVP (the demo):** one parent-driven creation flow (story brief with interests, an optional real moment and an optional "teach something" note · voice or typed narration, directions and "You continue" · kid's turn when the child is there) · live text → art → animation per page · fold-to-turn curl · pop-up · closing to finish, with a cover · save and show exactly (recorded clips, bookshelf) · non-Duo fallback for development.

**Out of scope for now**
- Physical iPhone Duo, haptics, motion sensors, camera input: the build and demo are simulator-only.
- iPad, Android, web.
- Multiple kid profiles and co-creation with a relative in another place.
- Offline generation.
- Languages other than English at the demo. The language setting is in the data model; other languages are untested.
- Selling or releasing anything: this is a free pitch and demo.

## 11. Assumptions and constraints

- **Duo APIs.** The iOS 27.1 SDK in Xcode 27.1 beta (27A9269) was checked on 2026-09-25 and contains the hinge API (status plus a continuous angle), the two-pane `ArrangementView`, and reserved regions for the fold and camera. There is **no dedicated cover-display API**, so the closed posture is assumed to run the app on the outer screen. Still unverified until the Phase 0 probe: whether the *simulator* delivers a continuous angle, and how it presents the closed/cover screen. An in-app hinge slider is the fallback for development and the demo.
- **Vendors:** Reactor (Orbis) for animation · Google Gemini for illustrations, layer images and animation prompts · OpenAI for speech-to-text, the story model, moderation and narration · Supabase for storage and the server functions that hold the keys. *Gemini covering images only is an assumption (decision D7).*
- The Orbis integration builds on a teammate's hackathon starter, used with permission (see the roadmap's reuse table).
- **Clip recording.** Exact replay (S13) assumes each page's Orbis stream can be recorded to a clip from the in-app web view. This is unverified until the Phase 0 probe (0.3). If it can't be done, a saved book shows the still and re-animates it live from the same picture and prompt, which is close but not exact.

## 12. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Orbis animation warps characters' faces or drifts off the page's content | Med | High | Motion prompts ask for gentle motion and a locked camera. Drift guard re-anchors. Phase 0 spike compares Orbis Stable and Dynamic. Fallback: animate only the background and keep characters as crisp cutouts |
| Orbis takes minutes to warm up | High | Med | Warm when the book starts (demo: well before going on stage). Show stills until ready |
| The demo runs short of Reactor credit, or a stray session keeps billing | Med | High (no animation on stage) | Demo credit budget (§9). Credit meter in the debug overlay. Kill switch and server-side cleanup of stray sessions. Saved books need no credit. Still-image fallback |
| Orbis clips can't be recorded from the in-app web view | Med | High (exact replay) | Phase 0 probe 0.3 tries recording inside the page first, then native capture of the web view. Last resort: still plus live re-animation (not exact) |
| A story the parent asked to teach something gets a fact wrong | Med | Med | The story model keeps facts simple and well known. In books made ahead, the parent sees every page first and can say "change that". Normal safety checks (K1) still apply |
| The simulator's hinge controls give only set postures, not a continuous angle | Med | High (curl and pop-up) | Phase 0 probe. In-app hinge slider as fallback |
| Folding to turn and folding to about 90° to pop up are the same motion | High | Med | Pick one gesture model in Phase 0 (decision D1) |
| Apple's Vision background removal doesn't run in the simulator (reportedly needs the Neural Engine) | High | High (pop-up) | Generate pop-up layers directly (background plate plus character cutouts). No segmentation needed |
| Art or animation latency misses the 5 s target | High | Med | Show text first, then a placeholder, then the still, then the animation. Prepare the next page early. Measure in Phase 0 |
| An unsafe picture or animation reaches a child | Low | Critical | Moderate before display. Animation prompts are generated only from checked content. Sampled frames act as a tripwire and switch back to the still |
| The Orbis session drops mid-demo | Med | High | Reconnect with backoff. Server-side cleanup. Kill switch. Still-image fallback |
| Mic picks up app audio (the animation's generated sound, narration) | High | Med | Mute animation audio while the mic is live. Headphones for the demo |
| Kids' voice and personal data | Med | High | Privacy by design: audio is transcribed and discarded, only the first name and interests are stored, keys stay on the server, and settings and sharing sit behind a parental gate |

## 13. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| D1 | Gesture model: how folding to turn and folding to pop up coexist | One continuous motion: folding past the turn threshold commits the page turn; keep folding to about 90° and the new page pops up; opening flat plays its animation |
| D2 | What "page appears in under 5 s" means | Text plus art placeholder within 5 s; still ≤ 10 s; animation ≤ 5 s after flip |
| D3 | Orbis Stable vs Dynamic | Stable (higher resolution, half the price); confirm in the Phase 0 spike |
| D4 | Record each page's animation clip | ✅ Resolved by P-01: required, because saved books replay exactly. Phase 0 settles how, and the clip length per page |
| D7 | Gemini's role | Images and animation prompts only. OpenAI keeps speech, story and narration |
| D8 | Timeline and demo date | ✅ Resolved: no deadline. The full scope is built, including all cut-list features |

*D5 and D6 were removed on 2026-09-26 (P-02): everything is free.*

---
*Next step: [ROADMAP.md](ROADMAP.md) turns these requirements into phases, tasks and cut lines.*
