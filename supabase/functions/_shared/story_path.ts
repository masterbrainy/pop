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
import { namesBrandedCharacter } from "./brand_check.ts";
import { detectsEndRequest } from "./end_request.ts";
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

// R-42: the request schema caps a bible's path at 12 beats of at most 300
// characters each (schemas.ts storyBibleSchema) — an overlong re-plan would
// make every later call to this same book a bad_request. Clamp here too, so
// a model that ignores the "5 to 8 beats" prompt guidance can never produce
// an unusable bible.
const MAX_PATH_BEATS = 12;
const MAX_BEAT_CHARS = 300;

/** Cuts a beat description to whole sentences within the 300-char cap (mirrors trimToLimit's word-limit approach for page text). */
function trimBeatToCharLimit(beat: string): string {
  const trimmed = beat.trim();
  if (trimmed.length <= MAX_BEAT_CHARS) return trimmed;
  const sentences = trimmed.split(/(?<=[.!?])\s+/);
  let kept = "";
  for (const sentence of sentences) {
    const candidate = kept ? `${kept} ${sentence}` : sentence;
    if (candidate.length > MAX_BEAT_CHARS) break;
    kept = candidate;
  }
  if (kept) return kept;
  return `${trimmed.slice(0, MAX_BEAT_CHARS - 1).trimEnd()}.`;
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

/** True when any of the three output texts leaked a foreign-script letter (see language_check.ts). `allowedNames` (R-42) exempts the kid's own name and bible character names. */
function hasForeignScript(
  pageText: string,
  artPrompt: string,
  readingQuestion: string,
  language: string,
  allowedNames: string[],
): boolean {
  return hasForeignScriptText(pageText, language, allowedNames) ||
    hasForeignScriptText(artPrompt, language, allowedNames) ||
    hasForeignScriptText(readingQuestion, language, allowedNames);
}

async function passesOutputGate(
  pageText: string,
  artPrompt: string,
  readingQuestion: string,
  readingLevel: ReadingLevel,
  language: string,
  safety: SafetyDeps,
  allowedNames: string[],
  extraGateTexts: (string | null)[] = [],
): Promise<{ safe: boolean; safetyMs: number }> {
  const start = performance.now();
  // R-42: bibleTitle and a successful parentNote reach the parent's screen
  // too, so they go through the same moderation + rubric gate as the page
  // text, art prompt and reading question (extraGateTexts).
  const gateTexts = [pageText, artPrompt, readingQuestion, ...extraGateTexts.map((t) => t ?? "")];
  const verdict = await runSafetyGate(gateTexts, readingLevel, safety);
  const wordLimitOk = withinWordLimit(pageText, readingLevel);
  const languageOk = !hasForeignScript(pageText, artPrompt, readingQuestion, language, allowedNames);
  // allowedNames always starts with the kid's own first name (see its callers).
  const brandOk = !namesBrandedCharacter(gateTexts, allowedNames[0]);
  return { safe: verdict.safe && wordLimitOk && languageOk && brandOk, safetyMs: Math.round(performance.now() - start) };
}

function rewriteReasonFor(
  pageText: string,
  artPrompt: string,
  readingQuestion: string,
  readingLevel: ReadingLevel,
  language: string,
  allowedNames: string[],
): string {
  if (!withinWordLimit(pageText, readingLevel)) {
    return "The page was too long for this reading level's word limit.";
  }
  if (hasForeignScript(pageText, artPrompt, readingQuestion, language, allowedNames)) {
    return "The page mixed in a word from another language or script. Write it again using only the brief's language.";
  }
  if (namesBrandedCharacter([pageText, artPrompt, readingQuestion], allowedNames[0])) {
    return "The page named a branded or famous character. Replace it with an original character of your own.";
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

  // R-42/ending-eval product rule: a direction that explicitly asks to end
  // the story now (docs/CONTRACTS.md) forces the re-planned path to end at
  // this very page, regardless of what the model returns.
  const forceEnd = input !== null && detectsEndRequest(input.text);

  const prepare = (attempt: PathModelAttempt): PathModelAttempt => ({
    ...attempt,
    output: { ...attempt.output, pageText: preparePageText(attempt.output.pageText, readingLevel, earlierTexts) },
  });

  /** R-42: the kid's own name and every known bible character name are never a "foreign script" leak. */
  const allowedNamesFor = (attempt: PathModelAttempt): string[] => [
    kidFirstName,
    ...existingBible.characters.map((c) => c.name),
    ...attempt.output.bibleCharacters.map((c) => c.name),
  ];

  const buildSuccess = (
    attempt: PathModelAttempt,
    timings: { modelMs: number; safetyMs: number },
  ): StoryPathResponseData => {
    const { path, isEnding } = planNewPath(existingBible.path, index, attempt.output.path, forceEnd);
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
  const firstNames = allowedNamesFor(first);
  const firstGate = await passesOutputGate(
    first.output.pageText,
    first.output.artPrompt,
    first.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
    firstNames,
    [first.output.bibleTitle, first.output.parentNote],
  );
  if (firstGate.safe) return buildSuccess(first, { modelMs: first.modelMs, safetyMs: firstGate.safetyMs });

  const second = prepare(
    await deps.callModel(
      rewriteReasonFor(first.output.pageText, first.output.artPrompt, first.output.readingQuestion, readingLevel, language, firstNames),
    ),
  );
  const secondNames = allowedNamesFor(second);
  const secondGate = await passesOutputGate(
    second.output.pageText,
    second.output.artPrompt,
    second.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
    secondNames,
    [second.output.bibleTitle, second.output.parentNote],
  );
  const modelMs = first.modelMs + second.modelMs;
  const safetyMs = firstGate.safetyMs + secondGate.safetyMs;
  if (secondGate.safe) return buildSuccess(second, { modelMs, safetyMs });

  return noneResponse(index, existingBible, { modelMs, safetyMs });
}

/**
 * Pure: the full new path is the beats already fixed before `index` plus the
 * newly (re)planned beats from `index` on — beats before `index` can never
 * change, regardless of what a model attempt echoes back. `index` ends the
 * story exactly when it's the last beat of that combined path.
 *
 * R-42: clamps the combined path to at most `MAX_PATH_BEATS` (matching the
 * request schema's cap), trimming each new beat to whole sentences within
 * `MAX_BEAT_CHARS`. When `forceEnd` is true (the parent's direction explicitly
 * asked to end the story now), only the first newly planned beat is kept, so
 * the path always ends at `index` regardless of what the model returned.
 */
export function planNewPath(
  existingPath: string[],
  index: number,
  newBeatsFromIndex: string[],
  forceEnd: boolean = false,
): { path: string[]; isEnding: boolean } {
  const kept = existingPath.slice(0, index);
  const roomForNew = forceEnd ? 1 : Math.max(1, MAX_PATH_BEATS - kept.length);
  const clampedNew = newBeatsFromIndex.slice(0, roomForNew).map(trimBeatToCharLimit);
  const path = [...kept, ...clampedNew];
  return { path, isEnding: path.length > 0 && index === path.length - 1 };
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
  kidFirstName: string,
  language: string,
  deps: RunPageTurnDeps,
  earlierTexts: string[] = [],
): Promise<StoryPathResponseData> {
  if (index >= existingBible.path.length) {
    return noneResponse(index, existingBible, { modelMs: 0, safetyMs: 0 }, PAST_ENDING_NOTE, null);
  }
  const isEnding = index === existingBible.path.length - 1;
  // R-42: the kid's own name and every known bible character name are never a "foreign script" leak.
  const allowedNames = [kidFirstName, ...existingBible.characters.map((c) => c.name)];

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
    allowedNames,
    [first.output.parentNote],
  );
  if (firstGate.safe) return buildSuccess(first, { modelMs: first.modelMs, safetyMs: firstGate.safetyMs });

  const second = prepare(
    await deps.callModel(
      rewriteReasonFor(first.output.pageText, first.output.artPrompt, first.output.readingQuestion, readingLevel, language, allowedNames),
    ),
  );
  const secondGate = await passesOutputGate(
    second.output.pageText,
    second.output.artPrompt,
    second.output.readingQuestion,
    readingLevel,
    language,
    deps.safety,
    allowedNames,
    [second.output.parentNote],
  );
  const modelMs = first.modelMs + second.modelMs;
  const safetyMs = firstGate.safetyMs + secondGate.safetyMs;
  if (secondGate.safe) return buildSuccess(second, { modelMs, safetyMs });

  return noneResponse(index, existingBible, { modelMs, safetyMs });
}
