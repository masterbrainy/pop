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

### P-01 · Parents drive creation; lessons inside stories kids love · 2026-09-25 · Status: proposed
- **Idea (Brian's words):** "The product is not simply for kids to imagine some stories. A core part of it is for PARENTS to actually be able to create these stories for their kids. For instance, they can tie in educational lessons inside of stories that their kids may like. Of course, it's also cool if the parents and kids can collaborate together to make the story, but don't forget that a major part of it is the parents actually driving this creation."
- **Changes:**
  - PRD tagline, §1 Problem, §3 Users, §4 Hypothesis, §6 principle 2 ("the kid leads" becomes "the parent drives, the kid can join in"), §7 Core experience, §10 MVP scope.
  - §8.1: new **story brief** (the lesson + what the kid loves + optional real-life moment) and a **kid profile with interests**. Learn and Real-life modes become that brief and move from P1 to P0. Typed input sits alongside voice. Kid co-creation stays P0 as the second way to make a book.
  - §8.6: fact-checking lessons (K2) moves from P1 to P0.
  - Roadmap: Phase 2 absorbs the brief, the interests and the lesson packs from Phase 6. Phases 0, 1, 3 and 4 (curl, animation, pop-up) don't change.
- **Cost:** docs about 1 h. Build about +6–8 h before the MVP line, mostly moved up from Phase 6, so about +3–4 h net overall. No new vendors or spend. Risk: wrong facts become a P0 risk (curated lesson packs first), and the demo's wow moment shifts from "the kid speaks and the book appears" to "a parent makes a lesson book in 2 minutes and the kid reads it".
- **Recommendation:** Do it, and do it now, while no code exists. The parent is the payer and the decider, so this makes the product stronger. It leaves the must-haves alone. Keep creation live: for each page, the parent tells it (voice or text) or taps "you continue", and the AI writes it following the lesson. That keeps live generation a must-have.
- **Decision:** —
