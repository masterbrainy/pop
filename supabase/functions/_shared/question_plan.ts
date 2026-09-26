// IMP-25 one question per page: which kind of question each page gets
// (questionKindFor), and the deterministic clean-up of what the model wrote
// (normalizeQuestion), so the app only ever sees a question that fits the
// plan. Pure functions; the question's own safety gate is question_gate.ts.
import { toChoiceSymbol } from "./choice_symbols.ts";
import type { ReadingLevel } from "./reading_levels.ts";
import { MAX_CHOICE_TEXT_CHARS } from "./schemas.ts";

export const QUESTION_KINDS = ["choice", "open", "talkOnly"] as const;
export type QuestionKind = (typeof QUESTION_KINDS)[number];

export interface PageChoice {
  label: string;
  symbol: string;
  /** One sentence telling the story engine what happens next if tapped. */
  direction: string;
  /** True for the one choice that matches the already-planned next beat. */
  followsPath: boolean;
}

/** The question as the model wrote it (after story_path_schema.ts's zod parse). */
export interface ModelQuestion {
  ask: string;
  kind: QuestionKind;
  choices: PageChoice[];
}

export interface QuestionPlan {
  kind: QuestionKind;
  choiceCount: 0 | 2 | 3;
}

/** What a page response carries (docs contract): `questionKind` only when `question` isn't "". */
export interface PageQuestion {
  question: string;
  questionKind?: QuestionKind;
  choices: PageChoice[];
}

export const NO_QUESTION: PageQuestion = { question: "", choices: [] };

const TALK_ONLY: QuestionPlan = { kind: "talkOnly", choiceCount: 0 };
const LISTENER_CHOICE_PAGES: ReadonlySet<number> = new Set([1, 3]);
const MIN_CHOICES = 2;

/**
 * The question plan for page `index` (contract "Question plan"): a listener
 * gets 2 choices on pages 1 and 3 only, an early reader 3 choices on every
 * page, a reader an open question with 3 choices as a floor — and every
 * ending is talk-only. `pathLength` null (or 0) means not known yet, so the
 * page isn't treated as the ending; path mode re-applies the plan once the
 * real planned path is known.
 */
export function questionKindFor(level: ReadingLevel, index: number, pathLength: number | null): QuestionPlan {
  const isEnding = pathLength !== null && pathLength > 0 && index === pathLength - 1;
  if (isEnding) return TALK_ONLY;
  switch (level) {
    case "listener":
      return LISTENER_CHOICE_PAGES.has(index) ? { kind: "choice", choiceCount: 2 } : TALK_ONLY;
    case "early_reader":
      return { kind: "choice", choiceCount: 3 };
    case "reader":
      return { kind: "open", choiceCount: 3 };
  }
}

function cleanChoice(choice: PageChoice): PageChoice | null {
  const label = choice.label.trim();
  const direction = choice.direction.trim();
  if (label === "" || direction === "" || direction.length > MAX_CHOICE_TEXT_CHARS) return null;
  return { label, symbol: toChoiceSymbol(choice.symbol), direction, followsPath: choice.followsPath };
}

/** At most one followsPath (the first true), kept even when truncating to `count` would cut it. */
function pickChoices(valid: PageChoice[], count: number): PageChoice[] {
  const firstFollowing = valid.findIndex((c) => c.followsPath);
  const marked = valid.map((c, i) => ({ ...c, followsPath: i === firstFollowing }));
  const kept = marked.slice(0, count);
  if (firstFollowing < count || kept.length === 0) return kept;
  return [...kept.slice(0, -1), marked[firstFollowing]];
}

/**
 * Makes the model's question fit `plan`: trims it, forces the plan's kind
 * (talk-only on the ending), drops unusable choices, keeps at most
 * `plan.choiceCount` with at most one followsPath, and falls back to
 * talk-only when a choice question has fewer than 2 usable choices. An empty
 * ask means no question at all.
 */
export function normalizeQuestion(raw: ModelQuestion, plan: QuestionPlan, isEnding: boolean): PageQuestion {
  const question = raw.ask.trim();
  if (question === "") return NO_QUESTION;
  const effective = isEnding ? TALK_ONLY : plan;
  if (effective.kind === "talkOnly") return { question, questionKind: "talkOnly", choices: [] };

  const valid = raw.choices.map(cleanChoice).filter((c): c is PageChoice => c !== null);
  const choices = pickChoices(valid, effective.choiceCount);
  if (choices.length >= MIN_CHOICES) return { question, questionKind: effective.kind, choices };
  return effective.kind === "choice"
    ? { question, questionKind: "talkOnly", choices: [] }
    : { question, questionKind: effective.kind, choices: [] };
}
