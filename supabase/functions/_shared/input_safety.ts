// Input-side kid-safety gate (R-37, PRD §8.6): moderate a turn's `input.text`
// before it ever reaches the story model, and — for a kid speaker only — run a
// cheap rubric check for words that sound like the child describing real harm
// happening to them, outside the story. Deps are injected (as safety.ts does)
// so this is fully unit-testable without any network call.
import type { ModerationResult, RubricResult } from "./safety.ts";
import { gentleParentNote } from "./safety.ts";

export interface InputSafetyDeps {
  moderateText: (text: string) => Promise<ModerationResult>;
  /** The kid real-harm rubric check (PRD §8.6); only ever called for a kid speaker. */
  checkRealHarm: (text: string) => Promise<RubricResult>;
}

/** Why an input (or, in story_path.ts/story_turn.ts, an output) was refused (docs/CONTRACTS.md `refusal`; R-41). */
export type Refusal = "real_harm" | "unsafe" | null;

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
 * handling of empty output text. A kid speaker also gets the real-harm rubric
 * check; a parent's flagged input gets the same gentle redirect note the
 * output gate uses, since nothing kid-specific applies to a parent's words.
 */
export async function checkInputSafety(
  text: string,
  speaker: "parent" | "kid",
  kidFirstName: string,
  deps: InputSafetyDeps,
): Promise<InputSafetyVerdict> {
  const trimmed = text.trim();
  if (trimmed === "") {
    return { blocked: false, parentNote: null, refusal: null };
  }

  const moderation = await deps.moderateText(trimmed);
  if (moderation.flagged) {
    return speaker === "kid"
      ? { blocked: true, parentNote: kidRealHarmNote(kidFirstName), refusal: "real_harm" }
      : { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" };
  }

  if (speaker === "kid") {
    const rubric = await deps.checkRealHarm(trimmed);
    if (!rubric.safe) {
      return { blocked: true, parentNote: kidRealHarmNote(kidFirstName), refusal: "real_harm" };
    }
  }

  return { blocked: false, parentNote: null, refusal: null };
}
