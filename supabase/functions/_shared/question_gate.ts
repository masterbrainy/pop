// IMP-25: the page question's own safety gate. runSafetyGate is
// all-or-nothing, so the question (its ask, choice labels and directions) is
// gated separately from — and in parallel with — the page: a flagged choice
// drops only the question, never the page. Same checks as the page gate:
// moderation + kid-safety rubric, foreign-script leak, branded character.
import { namesBrandedCharacter } from "./brand_check.ts";
import { hasForeignScriptText } from "./language_check.ts";
import { NO_QUESTION, type PageQuestion } from "./question_plan.ts";
import type { ReadingLevel } from "./reading_levels.ts";
import { runSafetyGate, type SafetyDeps } from "./safety.ts";

export interface GatedQuestion {
  question: PageQuestion;
  safetyMs: number;
}

/** Every text the parent or child will see (or the story engine will act on) for this question. */
export function questionTexts(question: PageQuestion): string[] {
  return [
    question.question,
    ...question.choices.map((c) => c.label),
    ...question.choices.map((c) => c.direction),
  ].filter((text) => text.trim().length > 0);
}

/**
 * The question unchanged when it passes, else NO_QUESTION (question "", no
 * kind, no choices). `allowedNames` starts with the kid's own first name and
 * is exempt from the foreign-script check (R-42) and the brand check.
 * An empty question makes no network call.
 */
export async function gateQuestion(
  question: PageQuestion,
  level: ReadingLevel,
  language: string,
  allowedNames: string[],
  safety: SafetyDeps,
): Promise<GatedQuestion> {
  const texts = questionTexts(question);
  if (texts.length === 0) return { question, safetyMs: 0 };
  const start = performance.now();
  const verdict = await runSafetyGate(texts, level, safety);
  const languageOk = !texts.some((text) => hasForeignScriptText(text, language, allowedNames));
  const brandOk = !namesBrandedCharacter(texts, allowedNames[0]);
  const safetyMs = Math.round(performance.now() - start);
  return { question: verdict.safe && languageOk && brandOk ? question : NO_QUESTION, safetyMs };
}
