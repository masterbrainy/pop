// The kid-safety gate (PRD §8.6, K1): moderation + a reading-level rubric
// check, run in parallel. Dependencies are injected so this orchestration is
// unit-testable without any network calls; story-turn/art/motion-prompt wire
// in the real OpenAI-backed implementations.
import type { ReadingLevel } from "./reading_levels.ts";

export interface ModerationResult {
  flagged: boolean;
  categories: string[];
}

export interface RubricResult {
  safe: boolean;
  reason: string;
}

export interface SafetyVerdict {
  safe: boolean;
  reason: string;
  flaggedCategories: string[];
}

export interface SafetyDeps {
  moderateText: (text: string) => Promise<ModerationResult>;
  checkRubric: (combinedText: string, readingLevel: ReadingLevel) => Promise<RubricResult>;
}

/**
 * Runs moderation on every non-empty text plus one rubric check on all of them
 * combined. Empty input (nothing to say) is trivially safe. Moderation and the
 * rubric check run concurrently to keep the gate off the latency budget.
 */
export async function runSafetyGate(
  texts: string[],
  readingLevel: ReadingLevel,
  deps: SafetyDeps,
): Promise<SafetyVerdict> {
  const nonEmpty = texts.map((t) => t.trim()).filter((t) => t.length > 0);
  if (nonEmpty.length === 0) {
    return { safe: true, reason: "", flaggedCategories: [] };
  }

  const combined = nonEmpty.join("\n\n");
  const [moderationResults, rubric] = await Promise.all([
    Promise.all(nonEmpty.map((text) => deps.moderateText(text))),
    deps.checkRubric(combined, readingLevel),
  ]);

  const flaggedCategories = Array.from(
    new Set(moderationResults.flatMap((r) => r.categories)),
  );
  const moderationFlagged = moderationResults.some((r) => r.flagged);

  if (moderationFlagged) {
    return {
      safe: false,
      reason: "Flagged by content moderation.",
      flaggedCategories,
    };
  }
  if (!rubric.safe) {
    return {
      safe: false,
      reason: rubric.reason || "Failed the kid-safety rubric.",
      flaggedCategories,
    };
  }
  return { safe: true, reason: "", flaggedCategories: [] };
}

/**
 * The fallback parent-facing note when a page still fails safety after one
 * rewrite attempt (PRD §8.6 responses: a gentle redirect, e.g. "Let's keep our
 * dragon friendly!"). The model's own rewrite is untrusted at this point, so
 * the note is a fixed, always-safe string rather than anything reason-derived.
 */
export function gentleParentNote(): string {
  return "Let's keep our story gentle here — try a friendlier direction and we'll carry on.";
}
