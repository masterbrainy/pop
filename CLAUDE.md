# Pop! — shared instructions for every Claude session in this project

Pop! is a live, co-created picture book for the iPhone Duo (Apple's foldable). A kid tells a story out loud; each page gets story text (left) and an illustration that comes alive as a per-page Orbis animation (right). Fold to turn the page, tilt to ~90° for a pop-up, close to finish the book.
**Read first:** [docs/PRD.md](docs/PRD.md) (what and why) · [docs/ROADMAP.md](docs/ROADMAP.md) (how, phases, verified platform facts).

## Build gate
**No feature code until Brian verifies the setup and says to start building.** Until then, only setup, docs, reviews and probes that Brian has approved. Before the gate opens:
1. Review & QA posts a readiness verdict at the top of `docs/REVIEW.md`.
2. The builder fixes any blocking findings.
3. Brian decides every **proposed** pivot in `docs/PIVOTS.md`.

The builder then starts with Phase 0 of the roadmap.

## Sessions and roles
All Pop! sessions live in the sidebar group **"Pop!"**. Set your own title to your role name so siblings can find you (`list_sessions` with group "Pop!").

| Session (title) | Session id | Role | Owns (only this session edits these) |
|---|---|---|---|
| **Pop! · Builder (lead)** | `local_fd25db33-d66a-47cc-9fb4-4c2fbee2e46a` | Builds the app phase by phase; integrates everything; final say on code; fixes readiness findings in its files | App code, `supabase/` (functions, migrations), `config/`, `CLAUDE.md`, ROADMAP (except when an accepted pivot is being applied), and **factual or editorial fixes to the PRD**. PRD scope, pricing and product-promise changes go through Pivots & Ideas for Brian to decide |
| **Pop! · Review & QA** | `local_883a05d7-0b22-46ae-a930-3e9efa9b9372` | Parallel checking: verifies claims, reviews every builder commit, runs builds and tests, makes small side improvements | `docs/REVIEW.md`, test-only additions, small fixes it announces to the builder |
| **Pop! · Pitch & Tech Log** | `local_8d1a05f7-51a4-4d59-a744-d7816d375b71` | Captures what matters for VCs and Apple engineers | `docs/PITCH.md`, `docs/TECH_NOTES.md` |
| **Pop! · Pivots & Ideas** | `local_9f48e2ec-d0fd-469b-b4a4-ec775fcafec4` | Brian's inbox for pivots and suggestions; assesses impact honestly | `docs/PIVOTS.md`; PRD (and ROADMAP scope) **only while applying a pivot Brian accepted** |

**Who tells whom.** Each entry is sender → recipients: what triggers the message.
- **Builder → QA:** after each commit batch or milestone ("review a1b2c3..d4e5f6").
- **Builder → Pitch & Tech Log:** after anything demo-worthy or measured (latency, a working posture effect, screenshots).
- **QA → Builder:** blocking findings (CRITICAL/HIGH) with REVIEW.md IDs.
- **QA → Pitch & Tech Log:** any correction to a fact that TECH_NOTES or PITCH relies on.
- **Pivots → Builder, QA, Pitch & Tech Log:** the moment Brian accepts a pivot (ID plus the commit that applied it), so QA re-audits and Pitch re-frames.
- **Pivots → Pitch & Tech Log:** ideas that are really pitch angles.
- **Pitch & Tech Log / QA → Builder:** suggested edits to PRD, ROADMAP or CLAUDE.md. Only the owner edits those files.

**Proposed pivots are not plan changes.** Work to the current PRD and ROADMAP. If a *proposed* entry in `docs/PIVOTS.md` would change your work, note the dependency (for example, "depends on P-01") rather than acting on it. Act only once its status is **accepted**.

## How sessions work together
- **Git.** Side sessions run in their own worktrees on their own branches. Integrate through `main`: commit only your own files by path (never `git add -A`), then `git fetch origin && git rebase origin/main && git push origin HEAD:main`. If the push is rejected, rebase and retry. The builder works directly on `main` in `/Users/brianhuang/Pop!`: commit, then `git pull --rebase` and push.
- **Messages.** Use `send_message` (or `SendMessage`) to another session's id for hand-offs: the builder pings QA after each commit batch or milestone, pings Pitch & Tech Log after anything demo-worthy, and Pivots pings the builder when Brian accepts a pivot. Keep messages short: what changed, which commits, and what you need.
- **Don't edit another session's files.** Propose the change to the owner instead.

## Where things get recorded
- **`docs/TECH_NOTES.md`:** dated technical facts and decisions, each with evidence (for example, verified API signatures, measured latency, workarounds).
- **`docs/PITCH.md`:** the pitch for two audiences (VCs; Apple engineers), a demo script, and an ideas inbox.
- **`docs/PIVOTS.md`:** Brian's pivots and suggestions, each with impact and status (proposed, accepted, parked, rejected).
- **`docs/REVIEW.md`:** QA findings with severity and status, plus the current readiness verdict.

## Secrets and private information
- API keys (Reactor, Gemini, OpenAI) live **only** in `/Users/brianhuang/Pop!/supabase/functions/.env` (ignored by git, readable only by Brian's account) and in Supabase secrets. **Never print, log, commit or paste their values.** When checking a key, print only HTTP status codes or `set / EMPTY`.
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
