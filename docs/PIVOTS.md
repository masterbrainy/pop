# Pop! — Pivots & Ideas

*Owner: the **Pop! · Pivots & Ideas** session · Judged against: [PRD.md](PRD.md) and [ROADMAP.md](ROADMAP.md)*

## How this works

1. Brian drops a pivot or idea in the Pivots & Ideas session, in any form.
2. It's logged here as **proposed**, with an honest take: what it changes, what it costs, what it risks, and whether we'd do it.
3. The status changes only when Brian decides: **accepted**, **parked** (good, not now) or **rejected**.
4. When a pivot is **accepted**, this session updates the PRD and/or roadmap to match, pushes to `main`, and tells the builder what changed (with the commit hash).
5. Ideas that are really pitch angles also go to the Pitch & Tech Log session.

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

### P-01 · Parents drive creation; lessons inside stories kids love · 2026-09-25 · Status: accepted
- **Idea (Brian's words):** "The product is not simply for kids to imagine some stories. A core part of it is for PARENTS to actually be able to create these stories for their kids. For instance, they can tie in educational lessons inside of stories that their kids may like. Of course, it's also cool if the parents and kids can collaborate together to make the story, but don't forget that a major part of it is the parents actually driving this creation."
- **Brian's clarification:** "I should be able to create the story ahead of time and save it or create the story with the child. These are both technically the same thing… I can tell it what I want it to add or change, and then it'll generate the next pages like that. When I'm satisfied, I can save this story then show to my child exactly the way I recorded it… Don't think of it as two entirely separate things."
- **Changes (as applied):**
  - PRD: intro, §1 Problem, §2 Evidence, §3 Users (the parent is the author), §4 Hypothesis, §5 (new "saved book replays exactly" gate), §6 (principle 2 is now "the parent drives"; new principle 6, "what you save is what they see"), §7 (one creation flow; the child being there is optional), §10 MVP scope.
  - PRD §8: the Imagine, Learn and Real-life modes become one **story brief** plus a **kid profile** (S4). New P0s: typed input (S2), directions (S7, was P1), "You continue" (S8), lesson woven in (S9), **save and show exactly** (S13), bookshelf and showing saved books (B1–B2, were P1), and lesson fact-checking (K2, was P1).
  - PRD §11–13: new assumption and risks for clip recording and wrong lessons; D4 (record clips) resolved as required.
  - Roadmap: Phase 0.3 must answer how to record clips. Phase 2 becomes parent-driven (brief, profile, typed input, directions, "You continue", lesson packs). Phase 3 records clips. The new **Phase 5, "Save and show"**, is above the MVP line. Phase 6 shrinks to lesson extras and parent controls. `BookStore` and `ClipReplayScene` are new units. Cut lines, tests, eval set and run-book are updated.
- **Cost (final):** the MVP line moves from about 60 h to about 78 h, and the total from 109 h to 118 h (+9 h net). v1 said 119 h, but its phases summed to 109 h. That's more than my first estimate of +3–4 h, because showing a saved book exactly makes saving, the bookshelf and clip recording must-haves. No new vendors. Orbis cost per book is unchanged, and showing a saved book is now free. Risks: recording clips from the web view is unproven (Phase 0.3), and lessons need to be accurate (curated packs first).
- **Recommendation:** Do it (given 2026-09-25).
- **Decision:** 2026-09-25, Brian accepted. Applied in `5c22f0d` (PRD v2, ROADMAP v2).

### P-02 · Pro as a monthly allowance of new books, not "unlimited" · 2026-09-25 · Status: proposed
- **Idea (source: Pitch & Tech Log, in PITCH.md "Unit economics"; not Brian's words):** "A fair-use allowance may beat 'unlimited'. PRD K5 still says unlimited."
- **Why it comes up:** making a book costs about $8.73 of Orbis time (15 live minutes). A family making four books a month costs about $35 a month in animation alone, so an "unlimited" Pro can lose money on exactly the families who love it most. Since P-01, showing a saved book costs nothing; only making new books costs money.
- **Changes:** PRD K5 ("Pro for unlimited" becomes "Pro includes N new books a month; showing saved books is always unlimited"), with N and the price set at D5 after measuring. Roadmap Phase 7: a monthly counter in the paywall (+0.5 h).
- **Cost:** about 0.5 h of build, no money. Risk: "unlimited" is simpler to sell; an allowance needs a friendly limit screen for the parent (never shown to the child).
- **Alternatives (raised by the builder):**
  - *Keep "unlimited" and record clips so rereads are free.* Clips are already required by P-01, but they don't cut the roughly $8.73 it costs to make each new book, so on their own they don't fix the problem.
  - *Animate only the first N pages of each book.* This cuts cost, but it weakens the living-page must-have (PRD P3) on every other page. It works better as a free-tier limit than as the Pro plan.
- **Recommendation:** Do it. It keeps the business honest without touching any must-have, and "unlimited rereads of every book you make" is still a strong line. Leave the numbers to D5.
- **Decision:** —
