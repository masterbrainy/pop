# Pop! — shared instructions for every Claude session in this project

Pop! lets a parent make a live picture book for their child on the iPhone Duo (Apple's foldable), either ahead of time or with the child watching. The parent tells or types the story and directs changes. Each page gets story text (left) and an illustration that comes alive as a per-page Orbis animation (right). Saved books replay exactly as made. Fold to turn the page, tilt to ~90° for a pop-up, close to finish the book.
**Read first:** [docs/PRD.md](docs/PRD.md) (what and why) · [docs/ROADMAP.md](docs/ROADMAP.md) (how, phases, verified platform facts).

## What this is: a hackathon-style pitch, not a release (Brian, 2026-09-26)
- **Everything is free.** Nothing is sold or released. Don't write pricing, paywalls, subscriptions, "Pro", unit-economics strategy, upsells, go-to-market or marketing plans, App Store or Kids Category planning, or legal-release checklists. If a VC asks how it makes money, one honest line is enough.
- **Keep:** anything that makes the demo great and reliable, kid safety (moderation), privacy by design, keys kept private, and a practical Reactor credit budget for the demo itself.
- **Parents drive creation.** Lessons are **optional**: a parent *can* ask for a story that teaches something. That's a use case of the story brief, **not** a subsystem to build (no lesson packs and no separate fact-check pipeline beyond the normal safety checks).

## Lead and interrupts
The builder coordinates all Pop! sessions. **A message from the builder overrides your current plan:** stop any conflicting work, keep useful uncommitted edits only if they still fit, and follow the new instructions. The builder may stop your turn in order to interject.

## Build gate
**No feature code until Brian verifies the setup and says to start building.** Until then, only setup, docs, reviews and probes that Brian has approved. Before the gate opens:
1. Brian decides every **proposed** pivot in `docs/PIVOTS.md`.
2. Review & QA posts a readiness verdict at the top of `docs/REVIEW.md`.
3. The builder fixes any blocking findings.

**When ready, everyone stops.** Once those three are done:
- Each side session commits and pushes its last work, sends the builder one line ("READY: <last commit>, nothing pending"), and then **does nothing more**.
- The builder reports to Brian and also stops.
- Nobody starts Phase 0 until **Brian says go**.

## Sessions and roles
All Pop! sessions live in the sidebar group **"Pop!"**. Set your own title to your role name so siblings can find you (`list_sessions` with group "Pop!").

| Session (title) | Session id | Role | Owns (only this session edits these) |
|---|---|---|---|
| **Pop! · Builder (lead)** | `local_fd25db33-d66a-47cc-9fb4-4c2fbee2e46a` | Builds the app phase by phase; integrates everything; final say on code; fixes readiness findings in its files; records verified facts and decisions | App code, `supabase/` (functions, migrations), `config/`, `CLAUDE.md`, ROADMAP (except when an accepted pivot is being applied), and **factual or editorial fixes to the PRD**. PRD scope, pricing and product-promise changes go through Pivots & Ideas for Brian to decide |
| **Pop! · Review & QA** | `local_883a05d7-0b22-46ae-a930-3e9efa9b9372` | Parallel checking: verifies claims, reviews every builder commit, runs builds and tests, makes small side improvements | `docs/REVIEW.md`, test-only additions, small fixes it announces to the builder |
| **Pop! · Pivots & Ideas** | `local_9f48e2ec-d0fd-469b-b4a4-ec775fcafec4` | Brian's inbox for pivots and suggestions; assesses impact honestly | `docs/PIVOTS.md`; PRD (and ROADMAP scope) **only while applying a pivot Brian accepted** |

*Brian retired and deleted **Pop! · Pitch & Tech Log**, and `docs/PITCH.md` and `docs/TECH_NOTES.md` are gone. Don't message that session or recreate those files.*

**Who tells whom.** Each entry is sender → recipients: what triggers the message.
- **Builder → QA:** after each commit batch or milestone ("review a1b2c3..d4e5f6").
- **QA → Builder:** blocking findings (CRITICAL/HIGH) with REVIEW.md IDs, and any correction to a fact in the PRD or ROADMAP.
- **QA → Pivots:** a finding only Brian can settle (scope or a product promise). Pivots logs it as a proposed pivot that cites the REVIEW.md ID, and QA marks the finding as waiting on that pivot.
- **Pivots → Builder and QA:** the moment Brian accepts a pivot (ID plus the commit that applied it), so the builder works to it and QA re-audits the changed docs.
- **QA / Pivots → Builder:** suggested edits to PRD, ROADMAP or CLAUDE.md. Only the owner edits those files.

**Proposed pivots are not plan changes.** Work to the current PRD and ROADMAP. If a *proposed* entry in `docs/PIVOTS.md` would change your work, note the dependency (for example, "depends on P-01") rather than acting on it. Act only once its status is **accepted**.

## How sessions work together
- **Git.** Side sessions run in their own worktrees on their own branches. Integrate through `main`: commit only your own files by path (never `git add -A`), then `git fetch origin && git rebase origin/main && git push origin HEAD:main`. If the push is rejected, rebase and retry. The builder works directly on `main` in `/Users/brianhuang/Pop!`: commit, then `git pull --rebase` and push.
- **Messages.** Use `send_message` (or `SendMessage`) with the other session's id for the hand-offs above. Keep messages short: what changed, which commits, and what you need.
- **Don't edit another session's files.** Propose the change to the owner instead.

## Where things get recorded
- **ROADMAP §3 (platform facts) and §10 (decision log):** verified technical facts, each with its source (SDK file, measurement or vendor doc), plus decisions. The builder writes them; others send corrections to the builder.
- **`docs/PIVOTS.md`:** Brian's pivots and suggestions, each with impact and status (proposed, accepted, parked, rejected).
- **`docs/REVIEW.md`:** QA findings with severity and status, plus the current readiness verdict.

## Secrets and private information
- API keys (Reactor, Gemini, OpenAI) live **only** in `/Users/brianhuang/Pop!/supabase/functions/.env` (ignored by git, readable only by Brian's account) and in Supabase secrets. **Never print, log, commit or paste their values.** When checking a key, print only HTTP status codes or `set / EMPTY`. **Don't hash, fingerprint or compare values either** (for example, local `.env` against `supabase secrets list` digests); Brian declined that. For Supabase secrets, list names only. When calling an API, pass the key through a header file (`-H @<(printf ...)`) so it never appears in the process list.
- App-side Supabase URL and publishable key: `/Users/brianhuang/Pop!/config/Supabase.local.xcconfig` (ignored by git).
- Supabase project ref: `/Users/brianhuang/Pop!/supabase/.temp/project-ref` (ignored by git). The CLI is already logged in. From a worktree, pass `--project-ref "$(cat /Users/brianhuang/Pop!/supabase/.temp/project-ref)"`.
- Don't copy any of these values into tracked files, docs or messages.

## Environment
- Xcode 27.1 beta at `/Applications/Xcode-beta.app` (selected). Only the iOS 27.1 simulator runtime is installed; the device is **iPhone Duo**. Build and demo **only in the simulator**: no physical Duo, camera, haptics or motion sensors.
- Supabase CLI (logged in, linked), Docker, Node 22, Swift 6.4, `gh` (logged in as masterbrainy; private repo `masterbrainy/pop`).
- The teammate's `jadroy/orbis-hackathon-starter` may be reused with permission (see ROADMAP §4).

## Working style
- Brian wants things done, not checklists: do every step you're allowed to do. Hand back only what must be his (his Mac password, account sign-ins and OAuth approvals, emptying the Trash, typing secrets into hidden Terminal prompts).
- Plain language, one recommended path, short replies.
- Test-first for logic modules (≥ 80% coverage), small focused files, no hardcoded secrets.
- If you're unsure an API signature or simulator behaviour is right, check the SDK or the simulator; don't guess.
