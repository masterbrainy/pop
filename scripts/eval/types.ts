// Shared shapes for the story eval harness (ROADMAP §8, PRD §5/§8.6).
// Kept dependency-free (no zod) so both run.ts and checks.ts can import them
// without pulling in the server's request-validation stack.
import type { ReadingLevel } from "../../supabase/functions/_shared/reading_levels.ts";

export type TurnKind = "speech" | "typed";
export type Speaker = "parent" | "kid";

/**
 * A direction turn (mode "path", with input), or `next: true` — the pre-P-04
 * "continue" tap's equivalent under path/page mode: write the next page along
 * the path with mode "page" and no input (docs/CONTRACTS.md "story-turn
 * modes path and page").
 */
export type EvalTurn =
  | { next: true; speaker: Speaker }
  | { kind: TurnKind; speaker: Speaker; text: string };

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
  /**
   * Only meaningful when mustBlockOrSoften is true (R-37): a kid real-harm
   * disclosure, not an unsafe request. When the turn is blocked (action
   * "none"), also requires a non-empty parentNote (PRD §8.6 "only the parent
   * sees a calm note"); when not blocked, the page must stay free of
   * unsafeIndicators, same as an ordinary red-team case.
   */
  requireParentNoteOnBlock?: boolean;
  /**
   * R-35(d): the session asks the story to reach an ending. After the
   * scripted turns, run.ts keeps calling mode "page" for the next index
   * (up to 8 extra calls) until a page comes back with `isEnding: true`, then
   * checks that page's text against a simple "reads like an ending"
   * heuristic and requires that isEnding was actually reached.
   */
  expectEnding?: boolean;
  /**
   * R-43: an everyday direction that mentions "the end of" something must not
   * end the story: no scripted turn may come back with `isEnding: true`.
   */
  expectNotEnding?: boolean;
  /**
   * R-42: every turn from a kid speaker must never come back with
   * `refusal: "real_harm"` — for playful/pretend content (for example
   * imaginary combat) that a content-moderation flag alone must not
   * misclassify as a real-harm disclosure.
   */
  mustNotBeRealHarm?: boolean;
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
  /** R-41: "real_harm" | "unsafe" | null — set only on a safety-refused "none". */
  refusal: string | null;
  /** True when this page is the story path's last beat (docs/CONTRACTS.md `page.isEnding`). */
  isEnding: boolean;
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
