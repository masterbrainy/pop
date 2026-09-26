// `story-turn` modes `path` and `page` orchestration (P-04, docs/CONTRACTS.md
// "story-turn modes path and page", PRD S5, S7, S12, S14): plan/replan the
// story path and write one page, running the same kid-safety output gate as
// `turn` (moderation + rubric, one rewrite, then `none`), plus the input-side
// gate (R-37) before any model call. Deps are injected (as story_turn.ts does)
// so this is fully unit-testable without any network call.
import type { ReadingLevel } from "./reading_levels.ts";
import { withinWordLimit } from "./reading_levels.ts";
import { gentleParentNote, runSafetyGate, type SafetyDeps } from "./safety.ts";
import { checkInputSafety, type InputSafetyDeps, type Refusal } from "./input_safety.ts";
import { hasForeignScriptText } from "./language_check.ts";
import { mergeBibleCharacters, stripRepeatedEarlierText, trimToLimit } from "./story_turn.ts";
import type { StoryBible } from "./schemas.ts";
import type { StoryPageModelOutput, StoryPathModelOutput } from "./story_path_schema.ts";

export interface PathPageResponse {
  index: number;
  text: string;
  artPrompt: string;
  question: string;
  isEnding: boolean;
}

export interface StoryPathResponseData {
  action: "page" | "none";
  page: PathPageResponse;
  bible: StoryBible;
  parentNote: string | null;
  /** Why a "none" was refused (R-41): "real_harm", "unsafe", or null (safe, or nothing left to write). */
  refusal: Refusal;
  timings: { modelMs: number; safetyMs: number };
}

const PAST_ENDING_NOTE = "The story has reached its ending.";

/**
 * Pure: the full new path is the beats already fixed before `index` plus the
 * newly (re)planned beats from `index` on — beats before `index` can never
 * change, regardless of what a model attempt echoes back. `index` ends the
 * story exactly when it's the last beat of that combined path.
 */
export function planNewPath(
  existingPath: string[],
  index: number,
  newBeatsFromIndex: string[],
): { path: string[]; isEnding: boolean } {
  const kept = existingPath.slice(0, index);
  const path = [...kept, ...newBeatsFromIndex];
  return { path, isEnding: path.length > 0 && index === path.length - 1 };
}

function noneResponse(
  index: number,
  existingBible: StoryBible,
  timings: { modelMs: number; safetyMs: number },
  parentNote: string = gentleParentNote(),
  refusal: Refusal = "unsafe",
): StoryPathResponseData {
  return {
    action: "none",
    page: { index, text: "", artPrompt: "", question: "", isEnding: false },
    bible: existingBible,
    parentNote,
    refusal,
    timings,
  };
}

/** Shared by both modes' output gate: drop retold earlier pages, then keep within the word limit. */
function preparePageText(pageText: string, level: ReadingLevel, earlierTexts: string[]): string {
  const stripped = stripRepeatedEarlierText(pageText, earlierTexts);
  return withinWordLimit(stripped, level) ? stripped.trim() : trimToLimit(stripped, level);
}

/** True when any of the three output texts leaked a foreign-script letter (see language_check.ts). */
function hasForeignScript(pageText: string, artPrompt: string, readingQuestion: string, language: string): boolean {
  return hasForeignScriptText(pageText, language) ||
    hasForeignScriptText(artPrompt, language) ||
    hasForeignScriptText(readingQuestion, language);
}

async function passesOutputGate(
  pageText: string,
  artPrompt: string,
  readingQuestion: string,
  readingLevel: ReadingLevel,
  language: string,
  safety: SafetyDeps,
): Promise<{ safe: boolean; safetyMs: number }> {
  const start = performance.now();
  const verdict = await runSafetyGate([pageText, artPrompt, readingQuestion], readingLevel, safety);
  const wordLimitOk = withinWordLimit(pageText, readingLevel);
  const languageOk = !hasForeignScript(pageText, artPrompt, readingQuestion, language);
  return { safe: verdict.safe && wordLimitOk && languageOk, safetyMs: Math.round(performance.now() - start) };
}

function rewriteReasonFor(pageText: string, artPrompt: string, readingQuestion: string, readingLevel: ReadingLevel, language: string): string {
  if (!withinWordLimit(pageText, readingLevel)) {
    return "The page was too long for this reading level's word limit.";
  }
  if (hasForeignScript(pageText, artPrompt, readingQuestion, language)) {
    return "The page mixed in a word from another language or script. Write it again using only the brief's language.";
  }
  return "The page did not pass the kid-safety rubric.";
}

export interface PathModelAttempt {
  output: StoryPathModelOutput;
  modelMs: number;
}

export interface RunPathTurnDeps {
  /** rewriteReason is null for the first attempt, else why the last attempt failed. */
  callModel: (rewriteReason: string | null) => Promise<PathModelAttempt>;
  safety: SafetyDeps;
  inputSafety: InputSafetyDeps;
}

/**
 * `mode: "path"` (docs/CONTRACTS.md): plans or re-plans the path from `index`
 * onward, then writes page `index`. `input` is null at the very start (the
 * brief alone drives the path); when present it's a direction, moderated
 * before any model call.
 */
export async function runPathTurn(
  readingLevel: ReadingLevel,
  index: number,
  existingBible: StoryBible,
  kidFirstName: string,
  language: string,
  input: { text: string; speaker: "parent" | "kid" } | null,
  deps: RunPathTurnDeps,
  earlierTexts: string[] = [],
): Promise<StoryPathResponseData> {
  if (input) {
    const verdict = await checkInputSafety(input.text, input.speaker, kidFirstName, deps.inputSafety);
    if (verdict.blocked) {
      return noneResponse(
        index,
        existingBible,
        { modelMs: 0, safetyMs: 0 },
        verdict.parentNote ?? gentleParentNote(),
        verdict.refusal,
      );
    }
  }

  const prepare = (attempt: PathModelAttempt): PathModelAttempt => ({
    ...attempt,
    output: { ...attempt.output, pageText: preparePageText(attempt.output.pageText, readingLevel, earlierTexts) },
  });

  const buildSuccess = (
    attempt: PathModelAttempt,
    timings: { modelMs: number; safetyMs: number },
  ): StoryPathResponseData => {
    const { path, isEnding } = planNewPath(existingBible.path, index, attempt.output.path);
    return {
      action: "page",
      page: {
        index,
        text: attempt.output.pageText,
        artPrompt: attempt.output.artPrompt,
        question: attempt.output.readingQuestion.trim(),
        isEnding,
      },
      bible: {
        title: attempt.output.bibleTitle,
        setting: attempt.output.bibleSetting,
        characters: mergeBibleCharacters(existingBible.characters, attempt.output.bibleCharacters),
        directions: attempt.output.bibleDirections,
        path,
      },
      parentNote: attempt.output.parentNote,
      refusal: null,
      timings,
    };
  };

  const first = prepare(await deps.callModel(null));
  const firstGate = await passesOutputGate(
    first.output.pageText,
    first.output.artPrompt,
    first.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
  );
  if (firstGate.safe) return buildSuccess(first, { modelMs: first.modelMs, safetyMs: firstGate.safetyMs });

  const second = prepare(
    await deps.callModel(rewriteReasonFor(first.output.pageText, first.output.artPrompt, first.output.readingQuestion, readingLevel, language)),
  );
  const secondGate = await passesOutputGate(
    second.output.pageText,
    second.output.artPrompt,
    second.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
  );
  const modelMs = first.modelMs + second.modelMs;
  const safetyMs = firstGate.safetyMs + secondGate.safetyMs;
  if (secondGate.safe) return buildSuccess(second, { modelMs, safetyMs });

  return noneResponse(index, existingBible, { modelMs, safetyMs });
}

export interface PageModelAttempt {
  output: StoryPageModelOutput;
  modelMs: number;
}

export interface RunPageTurnDeps {
  callModel: (rewriteReason: string | null) => Promise<PageModelAttempt>;
  safety: SafetyDeps;
}

/**
 * `mode: "page"` (docs/CONTRACTS.md): writes page `index` from the existing
 * `bible.path[index]`, with no re-planning and no input. Past the path's end
 * (the parent folded past the last beat) there's nothing left to write:
 * `action: "none"` with a short parentNote, and no model call.
 */
export async function runPageTurn(
  readingLevel: ReadingLevel,
  index: number,
  existingBible: StoryBible,
  language: string,
  deps: RunPageTurnDeps,
  earlierTexts: string[] = [],
): Promise<StoryPathResponseData> {
  if (index >= existingBible.path.length) {
    return noneResponse(index, existingBible, { modelMs: 0, safetyMs: 0 }, PAST_ENDING_NOTE, null);
  }
  const isEnding = index === existingBible.path.length - 1;

  const prepare = (attempt: PageModelAttempt): PageModelAttempt => ({
    ...attempt,
    output: { ...attempt.output, pageText: preparePageText(attempt.output.pageText, readingLevel, earlierTexts) },
  });

  const buildSuccess = (
    attempt: PageModelAttempt,
    timings: { modelMs: number; safetyMs: number },
  ): StoryPathResponseData => ({
    action: "page",
    page: {
      index,
      text: attempt.output.pageText,
      artPrompt: attempt.output.artPrompt,
      question: attempt.output.readingQuestion.trim(),
      isEnding,
    },
    bible: existingBible,
    parentNote: attempt.output.parentNote,
    refusal: null,
    timings,
  });

  const first = prepare(await deps.callModel(null));
  const firstGate = await passesOutputGate(
    first.output.pageText,
    first.output.artPrompt,
    first.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
  );
  if (firstGate.safe) return buildSuccess(first, { modelMs: first.modelMs, safetyMs: firstGate.safetyMs });

  const second = prepare(
    await deps.callModel(rewriteReasonFor(first.output.pageText, first.output.artPrompt, first.output.readingQuestion, readingLevel, language)),
  );
  const secondGate = await passesOutputGate(
    second.output.pageText,
    second.output.artPrompt,
    second.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
  );
  const modelMs = first.modelMs + second.modelMs;
  const safetyMs = firstGate.safetyMs + secondGate.safetyMs;
  if (secondGate.safe) return buildSuccess(second, { modelMs, safetyMs });

  return noneResponse(index, existingBible, { modelMs, safetyMs });
}
