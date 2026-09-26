// Shared shapes for the story eval harness (ROADMAP §8, PRD §5/§8.6).
// Kept dependency-free (no zod) so both run.ts and checks.ts can import them
// without pulling in the server's request-validation stack.
import type { ReadingLevel } from "../../supabase/functions/_shared/reading_levels.ts";

export type TurnKind = "speech" | "typed" | "continue";
export type Speaker = "parent" | "kid";

export interface EvalTurn {
  kind: TurnKind;
  speaker: Speaker;
  /** Empty string is valid for a "continue" ("You continue") turn. */
  text: string;
}

export interface EvalBrief {
  kidFirstName: string;
  readingLevel: ReadingLevel;
  interests: string[];
  /** The optional "Anything you'd like this story to teach?" field. */
  teach?: string | null;
  realMoment?: string | null;
}

export interface EvalExpectation {
  /** True for a red-team (PRD §8.6) case: the request itself is unsafe. */
  mustBlockOrSoften?: boolean;
  /**
   * Case-insensitive substrings that would prove the unsafe request leaked
   * through un-softened. Checked against the final turn's page text and art
   * prompt only when mustBlockOrSoften is true.
   */
  unsafeIndicators?: string[];
  /**
   * Case-insensitive substrings (surnames, addresses, schools, phone
   * numbers, preachy lecture phrases, ...) that must never appear in any
   * turn's page text for this session.
   */
  mustNotContain?: string[];
  /** Default true: apply the reading level's word-limit check to every turn. */
  checkReadingLevel?: boolean;
  /** Default true: apply the non-empty/coherence heuristic to every turn that produced text. */
  checkCoherent?: boolean;
  /** Human-readable note shown in the report for context; not itself checked. */
  note?: string;
}

export interface EvalCase {
  id: string;
  category: string;
  description: string;
  brief: EvalBrief;
  turns: EvalTurn[];
  expect: EvalExpectation;
}

export interface TurnOutcome {
  turnIndex: number;
  action: string;
  pageIndex: number;
  pageText: string;
  artPrompt: string;
  parentNote: string | null;
  modelMs: number;
  safetyMs: number;
  httpStatus: number;
  errorCode?: string;
}

export interface CaseResult {
  id: string;
  category: string;
  pass: boolean;
  reasons: string[];
  isSafetyCase: boolean;
  isFalseBlock: boolean;
  elapsedMs: number;
  turns: TurnOutcome[];
}

export interface EvalSummary {
  ranAt: string;
  totalCases: number;
  passCount: number;
  failCount: number;
  safetyCaseCount: number;
  safetyMissCount: number;
  safeCaseCount: number;
  falseBlockCount: number;
  falseBlockRate: number;
  slowestCaseId: string | null;
  slowestCaseMs: number;
}
