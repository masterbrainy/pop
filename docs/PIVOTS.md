# Pop! — Pivots & Ideas

*Owner: the **Pop! · Pivots & Ideas** session · Judged against: [PRD.md](PRD.md) and [ROADMAP.md](ROADMAP.md)*

## How this works

1. Brian drops a pivot or idea in the Pivots & Ideas session, in any form. Review & QA may also send findings that only Brian can settle; each is logged here as a proposed pivot that cites its `REVIEW.md` ID.
2. It's logged here as **proposed**, with an honest take: what it changes, what it costs, what it risks, and whether we'd do it.
3. The status changes only when Brian decides: **accepted**, **parked** (good, not now) or **rejected**.
4. When a pivot is **accepted**, this session updates the PRD and/or roadmap to match, pushes to `main`, and tells the builder and Review & QA the pivot ID and the commit hash.

**Red lines.** Ideas get pushback if they weaken a must-have (live generation, page curl, pop-up) or kid safety (PRD §8.6 K1, §12).

**Entry format**

```
### P-NN · Short title · YYYY-MM-DD · Status: proposed
- **Idea (Brian's words):** "…"
- **Changes:** PRD §… · Roadmap phase … · tech …
- **Cost:** ~N h · $… · risk: …
- **Recommendation:** do it / park it / don't, and why, in one or two lines.
- **Decision:** (date, Brian's call, and the commit that applied it)
```

## Log

### P-01 · Parents drive creation (lessons optional) · 2026-09-26 · Status: accepted, refined 2026-09-26
- **Idea (Brian's words):** "The product is not simply for kids to imagine some stories. A core part of it is for PARENTS to actually be able to create these stories for their kids. For instance, they can tie in educational lessons inside of stories that their kids may like. Of course, it's also cool if the parents and kids can collaborate together to make the story, but don't forget that a major part of it is the parents actually driving this creation."
- **Brian's clarification:** "I should be able to create the story ahead of time and save it or create the story with the child. These are both technically the same thing… I can tell it what I want it to add or change, and then it'll generate the next pages like that. When I'm satisfied, I can save this story then show to my child exactly the way I recorded it… Don't think of it as two entirely separate things."
- **Changes (as applied):**
  - PRD: intro, §1 Problem, §2 Evidence, §3 Users (the parent is the author), §4 Hypothesis, §5 (new "saved book replays exactly" gate), §6 (principle 2 is now "the parent drives"; new principle 6, "what you save is what they see"), §7 (one creation flow; the child being there is optional), §10 MVP scope.
  - PRD §8: the Imagine, Learn and Real-life modes become one **story brief** plus a **kid profile** (S4). New P0s: typed input (S2), directions (S7, was P1), "You continue" (S8), lesson woven in (S9), **save and show exactly** (S13), bookshelf and showing saved books (B1–B2, were P1), and lesson fact-checking (K2, was P1).
  - PRD §11–13: new assumption and risks for clip recording and wrong lessons; D4 (record clips) resolved as required.
  - Roadmap: Phase 0.3 must answer how to record clips. Phase 2 becomes parent-driven (brief, profile, typed input, directions, "You continue", lesson packs). Phase 3 records clips. The new **Phase 5, "Save and show"**, is above the MVP line. Phase 6 shrinks to lesson extras and parent controls. `BookStore` and `ClipReplayScene` are new units. Cut lines, tests, eval set and run-book are updated.
- **Cost (final):** the MVP line moves from about 60 h to about 78 h, and the total from 109 h to 118 h (+9 h net). v1 said 119 h, but its phases summed to 109 h. That's more than my first estimate of +3–4 h, because showing a saved book exactly makes saving, the bookshelf and clip recording must-haves. No new vendors. Orbis cost per book is unchanged, and showing a saved book is now free. Risks: recording clips from the web view is unproven (Phase 0.3), and lessons need to be accurate (curated packs first).
- **Recommendation:** Do it (given 2026-09-26).
- **Decision:** 2026-09-26, Brian accepted. Applied in `5c22f0d` (PRD v2, ROADMAP v2).
- **Refinement (2026-09-26, Brian, relayed by the builder and recorded in CLAUDE.md "What this is"):** parents drive creation, and that stays. Lessons are **optional**: a use case of the story brief, not a subsystem. Removed: curated lesson packs, lesson fact-checking (K2), and lesson extras (S9, S10, word of the story, remember-when questions). The brief keeps an optional free-text "Anything you'd like this story to teach?". Normal kid-safety moderation (K1) stays P0. New totals: MVP about 75 h, total about 109 h. Applied in PRD v3 and ROADMAP v3 (commit below, under P-02).

### P-02 · Pro as a monthly allowance of new books, not "unlimited" · 2026-09-26 · Status: rejected (superseded: everything is free)
- **Idea (source: the former Pitch & Tech Log session, relayed by the builder; not Brian's words):** "A fair-use allowance may beat 'unlimited'. PRD K5 still says unlimited."
- **Why it comes up:** making a book costs about $8.73 of Orbis time (15 live minutes). A family making four books a month costs about $35 a month in animation alone, so an "unlimited" Pro can lose money on exactly the families who love it most. Since P-01, showing a saved book costs nothing; only making new books costs money.
- **Changes:** PRD K5 ("Pro for unlimited" becomes "Pro includes N new books a month; showing saved books is always unlimited"), with N and the price set at D5 after measuring. Roadmap Phase 7: a monthly counter in the paywall (+0.5 h).
- **Cost:** about 0.5 h of build, no money. Risk: "unlimited" is simpler to sell; an allowance needs a friendly limit screen for the parent (never shown to the child).
- **Alternatives (raised by the builder):**
  - *Keep "unlimited" and record clips so rereads are free.* Clips are already required by P-01, but they don't cut the roughly $8.73 it costs to make each new book, so on their own they don't fix the problem.
  - *Animate only the first N pages of each book.* This cuts cost, but it weakens the living-page must-have (PRD P3) on every other page. It works better as a free-tier limit than as the Pro plan.
- **Recommendation:** Do it. It keeps the business honest without touching any must-have, and "unlimited rereads of every book you make" is still a strong line. Leave the numbers to D5.
- **Decision:** 2026-09-26, Brian (relayed by the builder, recorded in CLAUDE.md "What this is"): **everything is free**. Pop! is a hackathon-style pitch and demo, not a release, so there's no Pro plan to shape. Removed from the PRD: the paywall (K5), pricing (D5), the Kids Category decision (D6), the post-demo metrics, purchase gates, and the legal-review item (the privacy-by-design facts stay). Crash reporting becomes local timing logs plus the debug overlay (K6). The cost-per-book risk becomes a demo Reactor credit budget. Removed from the roadmap: the business items in Phase 7, and D5/D6. Applied in `8e4453d` (PRD v3, ROADMAP v3).

### P-03 · iPhone Duo only · 2026-09-26 · Status: accepted
- **Idea (Brian's words):** "Everything is ONLY for iPhone Duo. Do not worry about building for other iPhone layouts."
- **Changes (as applied):**
  - PRD: H5 (the non-Duo single-page reader) is removed. The MVP's "non-Duo fallback" becomes "iPhone Duo only". Other iPhones are added to out of scope. The Save button no longer promises "any device".
  - Roadmap: `HingeSource` keeps only the Duo version and the debug slider. The non-Duo reader is out of Phase 1 (10 h to 8 h). UI tests run on the Duo simulator.
  - New totals: MVP about 73 h, total about 107 h.
- **Cost:** saves about 2 h. No risk for the demo; the in-app hinge slider stays as the development fallback on the Duo.
- **Recommendation:** Do it. It matches the simulator-only, Duo-only demo.
- **Decision:** 2026-09-26, Brian decided directly in this session.

### P-04 · Story path, with the next page built behind the current one · 2026-09-26 · Status: accepted
- **Idea (Brian's words):** "There shouldn't be severe time latency issues. We're storing pages behind the current one. Ahead of time we'll have a story path generated from the first prompt which can adjust as the user prompts it more during the middle. But there's always a definitive path to some end, even if the end will change… the live model animation for event 1 [is] like some dragon flying into a tree, where the live model aspect would simply have it like repeated animation bobbing up and down after it's unconscious on the ground… The user can say they want the dragon to be woken up again, and then it will create a new story path… a new live model generation for a separate scene that is consistent with the first scene, creating a page behind the current. When flipping the page, it will display that scene, with its new dialogue."
- **Changes (as applied):**
  - PRD §7: the brief produces a story path that always reaches an ending, and the next page is always built behind the one on screen. Directions re-plan the path from the page behind and never change the page on screen. Each page's animation is a gentle, repeating motion of its moment.
  - PRD §8: S5, S7 and S12 are rewritten, and S14 (story path) is new. S8 ("You continue") is removed, because the path always has a next page. P4 now specifies the repeating motion, and S13 saves only pages that were shown.
  - PRD §5, §9, §12 and D2: the latency budget is now brief → page 1, direction → page behind rebuilt, and fold → next page shown at once. D2 is resolved.
  - Roadmap: the `StoryEngine` and `PagePipeline` units, Phase 2 bullets and exit, the 2-day cut line, unit tests and the eval set. Hours are unchanged: path planning replaces the speech page-break and revise-current work.
- **Cost:** about neutral in hours. The code already built needs rework: `story-turn` currently returns `append / new_page / revise_current`, and it now needs to plan and re-plan a path instead. Risk: a single Orbis session can only animate one page, so the new page's animation starts after the fold (its still shows first, about the reset-to-first-frame time measured in probe 0.3). A second warm session could pre-roll the page behind, at double the credit.
- **Recommendation:** Do it. It hides almost all generation latency and makes the story always land. Keep one Orbis session unless probe 0.3 shows a noticeable gap after the fold.
- **Decision:** 2026-09-26, Brian decided directly in this session.

### P-05 · Use OpenAI for images and remove Gemini · 2026-09-26 · Status: partly reverted (pictures back on Gemini; animation prompts stay on OpenAI)
- **Idea (Brian's words):** "Should I use the OpenAI key for image generation and then completely remove Gemini?"
- **Measured today** (prompt "a green dragon dazed under an oak tree, watercolor"; times are the full API round trip):

  | Model | Size, quality | HTTP | Time | Price per picture |
  |---|---|---|---|---|
  | `gpt-image-2.5-flare` | **1536×1024, medium** (the page size; cropped to 1536×864 = 16:9, subject stays centred) | 200 ×3 | **12.8 s, 13.0 s, 11.9 s** | **≈ $0.011** (343 image tokens × $30/1M + 49 text tokens × $5/1M) |
  | `gpt-image-2.5-flare` | 1536×1024, low | 200 | 10.4 s | ≈ $0.005 (158 image tokens) |
  | `gpt-image-2.5-flare` | 1024×1536 portrait, medium | 200 | 14.4 s | — |
  | `gpt-image-1-mini` | 1024×1536 portrait, medium | 200 | 15.5 s | cheaper ($8/1M image tokens) |
  | `gpt-image-2` | 1024×1536 portrait, medium | 200 | 35.2 s | too slow |
  | `gemini-2.5-flash-image` | 16:9 | **402** | — | "Prepayment credits are depleted", so Gemini art is down right now. Earlier probe: 1344×768 in about 5 s. Price $0.04–0.13 per picture (ROADMAP §3) |

  Token counts come from each response's `usage` field. Per-token prices are from OpenAI's pricing page (developers.openai.com/api/docs/pricing, checked 2026-09-26). OpenAI has no native 16:9 size, so `art` would ask for 1536×1024 and crop to 16:9, as in the row above (REVIEW.md R-47).

- **Changes:** PRD §11 vendors and D7, and the §5 "art ≤ 10 s after text" row (it becomes about 13 s). Roadmap: the `Art` unit (1536×1024, then crop to 16:9), `motion-prompt` (the OpenAI story model reads the page text and still instead of Gemini), Phase 4 layer generation, Phase 8 drawing restyle, run-book step 6. Code: `_shared/gemini_client.ts` is replaced by an OpenAI images client, and the `art` and `motion-prompt` functions are rewired.
- **Cost:** about 3 h (rewire the two functions, then re-run probe 0.4 on OpenAI: character reference edits, cutouts and the 16:9 crop). Pictures get **cheaper**, about $0.011 against Gemini's $0.04–0.13. One fewer key, one fewer bill, and no more out-of-credit outages on a second vendor.
- **Risks:** a picture takes about 2.5× as long (about 13 s against 5 s). The page behind (P-04) hides this on every page except page 1 and right after a direction. `gpt-image-2.5-flare` is two weeks old, so check that edits with reference images and transparent backgrounds (which would remove the chroma-key step for pop-up cutouts) work before relying on them. Each timing is one sample per setting (three at the page size).
- **Recommendation:** Do it, with `gpt-image-2.5-flare`. Simpler, one vendor for everything but Orbis, and the extra 9 s is mostly hidden. To speed up page 1, use `quality: "low"` just for it (about 10 s). If you'd rather keep Gemini's speed, top up its credits instead; but then you're paying and watching two vendors.
- **Decision:** 2026-09-26, Brian accepted (to the builder: "update the supabase to use the new openai key for all functionalities"). Code in `882d0fa` (art on `gpt-image-2.5-flare` at 1536×1024 medium with edits for references, motion-prompt on the story model, Gemini code removed, ROADMAP D7). PRD §5, §9, §11 and D7 updated in the next commit.
- **Reversal (2026-09-26, Brian to the builder: "switch the image generation all back to gemini"):** `d55a1a5` puts every picture back on `gemini-2.5-flash-image` (live: HTTP 200 in 8.2 s, 1344×768). `motion-prompt` stays on OpenAI's story model. PRD §5 (art ≤ 10 s after the text), §9, §11 and D7 were updated to match in the next commit.

### P-06 · Close-to-turn pages and a Finish button (already built) · 2026-09-26 · Status: proposed
- **Idea (source: Taeyeon's PR #2, `452dd1d`, merged and deployed by the builder; flagged by Review & QA as REVIEW.md R-48; not Brian's words):** "A page turns only when the Duo folds to 80° or below and opens past 100°, or from a small corner arrow. Folding less never turns; ~90° still pops. Closing never finishes the book or jumps back to page 1; Finish saves."
- **What it changes against the plan:**
  - **Turning:** before, folding past about 140° turned the page (PRD D1, H1, §7 step 5). Now you fold almost shut (≤ 80°) and reopen past 100°. On the way down, the page now showing pops up (starting at 130°, full at 90°), so every turn passes through a pop-up. A small corner arrow also turns the page.
  - **Finishing:** closing the phone no longer finishes the book; a Finish button saves it (PRD H3, which REVIEW R-15 made P0; §7 step 7; CLAUDE.md "close to finish the book").
  - Unchanged: the pop-up at about 90°, and its 13 new `PostureMachine` tests.
- **Cost:** keeping it means about 0.5 h of doc edits (PRD D1, H1, H3, §7 steps 5–7 and §5's curl row; ROADMAP Phase 1 and D1; CLAUDE.md's one-line description, which the builder owns). Going back means about 2–3 h of code and tests to restore the old gesture. Either way, the builder deletes the leftover close-to-finish code (`BookReader.closedAt` / `onClosedHold`, now unwired), or wires it for the last-page variant (Review & QA note on R-48).
- **Risks:** it's harder to turn a page by accident, and closing never loses a book mid-story, which suits a live demo. But the signature "close the phone to finish" moment is gone, and each turn is a bigger motion. Not yet tried by me in the simulator.
- **Recommendation:** Keep it. It's built, tested and more reliable on stage, and the pop-up still happens on every page. If you want the "close to finish" moment back, the least risky version is: closing on the **last** page of the story path shows the cover and finishes; closing anywhere else does nothing.
- **Decision:** —
