// Input-side kid-safety gate (R-37, PRD §8.6): moderate a turn's `input.text`
// before it ever reaches the story model, and — for a kid speaker only — run a
// cheap rubric check for words that sound like the child describing real harm
// happening to them, outside the story. Deps are injected (as safety.ts does)
// so this is fully unit-testable without any network call.
import type { ModerationResult, RubricResult } from "./safety.ts";
import { gentleParentNote } from "./safety.ts";

export interface InputSafetyDeps {
  moderateText: (text: string) => Promise<ModerationResult>;
  /** The kid real-harm rubric check (PRD §8.6); called for a kid speaker, and for any speech (R-44). */
  checkRealHarm: (text: string) => Promise<RubricResult>;
  /**
   * A second opinion on a parent's own moderation-flagged direction (R-41
   * root-cause fix): only ever called for a parent speaker, and only when
   * moderation flagged their words. Never called for a kid speaker — a kid's
   * words are never given this override (see checkRealHarm above).
   */
  checkDirectionSafety: (text: string) => Promise<RubricResult>;
}

/** Why an input (or, in story_path.ts/story_turn.ts, an output) was refused (docs/CONTRACTS.md `refusal`; R-41). */
export type Refusal = "real_harm" | "unsafe" | null;

/** How the words arrived: spoken, typed, or a tapped choice tile (IMP-25). */
export type InputKind = "speech" | "typed" | "choice";

export interface InputSafetyVerdict {
  blocked: boolean;
  /** Non-null exactly when blocked is true. */
  parentNote: string | null;
  /** Non-null exactly when blocked is true: "real_harm" for a kid speaker, "unsafe" for a parent. */
  refusal: Refusal;
}

/** PRD §8.6: "a kid's words that sound like real harm ... only parentNote mentions them." */
export function kidRealHarmNote(kidFirstName: string): string {
  return `${kidFirstName} said something that might matter outside the story. ` +
    "It's been kept out of the book; you may want to talk about it together.";
}

/**
 * Moderates `text` before any model call. Empty input (nothing said) is
 * trivially safe and skips both network calls, matching runSafetyGate's
 * handling of empty output text.
 *
 * R-42: for a kid speaker, moderation alone never decides "real_harm" versus
 * "unsafe" — a moderation flag can trip on playful pretend content ("the
 * dragon fights the knight") that isn't a real-harm disclosure. The dedicated
 * real-harm rubric (R-37) always runs for a kid speaker (concurrently with
 * moderation) and is what decides: if it says the words sound like real harm,
 * the block uses the calm real-harm note and `refusal: "real_harm"`; if the
 * rubric says it's safe pretend play but moderation still flagged it, the
 * block still happens (moderation's own judgment isn't ignored), but with the
 * generic gentle redirect and `refusal: "unsafe"`, same as a parent's words.
 * A parent's flagged input gets a second opinion instead (R-41 root-cause
 * fix): moderation can flag a completely ordinary, benign direction as a
 * false positive (observed live: "Let's finish the story here with a proper
 * ending." tripped moderation's "violence" category). A parent is the
 * trusted adult steering the story, so when moderation flags their words,
 * checkDirectionSafety gets a fast second opinion; only when it agrees the
 * words are unsafe does the direction get blocked, with the generic gentle
 * redirect note and `refusal: "unsafe"`.
 */
export async function checkInputSafety(
  text: string,
  speaker: "parent" | "kid",
  kidFirstName: string,
  deps: InputSafetyDeps,
  kind: InputKind = "typed",
): Promise<InputSafetyVerdict> {
  const trimmed = text.trim();
  if (trimmed === "") {
    return { blocked: false, parentNote: null, refusal: null };
  }

  // IMP-25: a tapped choice is words the story engine itself wrote (and gated)
  // for this page, but the app could send any text as a "choice", so it is
  // re-moderated. There's no real-harm rubric (a tile isn't a disclosure) and
  // no parent second opinion (it's the kid's turn).
  if (kind === "choice") {
    const moderation = await deps.moderateText(trimmed);
    return moderation.flagged
      ? { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" }
      : { blocked: false, parentNote: null, refusal: null };
  }

  // R-44: the speaker toggle defaults to the parent, so spoken words may be the
  // kid's. Speech always gets the real-harm check; a parent's typed words don't.
  if (speaker === "parent" && kind === "speech") {
    const [moderation, rubric] = await Promise.all([deps.moderateText(trimmed), deps.checkRealHarm(trimmed)]);
    if (!rubric.safe) {
      return { blocked: true, parentNote: kidRealHarmNote(kidFirstName), refusal: "real_harm" };
    }
    return await secondOpinionFor(trimmed, moderation.flagged, deps);
  }

  if (speaker === "kid") {
    const [moderation, rubric] = await Promise.all([
      deps.moderateText(trimmed),
      deps.checkRealHarm(trimmed),
    ]);
    if (!rubric.safe) {
      return { blocked: true, parentNote: kidRealHarmNote(kidFirstName), refusal: "real_harm" };
    }
    if (moderation.flagged) {
      return { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" };
    }
    return { blocked: false, parentNote: null, refusal: null };
  }

  const moderation = await deps.moderateText(trimmed);
  return await secondOpinionFor(trimmed, moderation.flagged, deps);
}

export const SAFE_INPUT: InputSafetyVerdict = { blocked: false, parentNote: null, refusal: null };

/**
 * Combines several input checks' verdicts: a real-harm block wins (its note
 * is the one the parent most needs), then the first other block, else safe.
 */
export function firstBlockingVerdict(verdicts: InputSafetyVerdict[]): InputSafetyVerdict {
  return verdicts.find((v) => v.blocked && v.refusal === "real_harm") ?? verdicts.find((v) => v.blocked) ?? SAFE_INPUT;
}

/** A parent's direction: blocked only when moderation flagged it and the second opinion agrees. */
async function secondOpinionFor(text: string, flagged: boolean, deps: InputSafetyDeps): Promise<InputSafetyVerdict> {
  if (flagged && !(await deps.checkDirectionSafety(text)).safe) {
    return { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" };
  }
  return { blocked: false, parentNote: null, refusal: null };
}
