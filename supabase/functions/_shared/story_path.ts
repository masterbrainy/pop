// `story-turn` modes `path` and `page` orchestration (P-04, docs/CONTRACTS.md
// "story-turn modes path and page", PRD S5, S7, S12, S14): plan/replan the
// story path and write one page, running the same kid-safety output gate as
// `turn` (moderation + rubric, one rewrite, then `none`), plus the input-side
// gate (R-37) before any model call. Deps are injected (as story_turn.ts does)
// so this is fully unit-testable without any network call.
//
// IMP-24/25: the brief's free text is checked alongside the direction before
// any model call (checkBrief); each page carries a question fitted to the
// question plan (question_plan.ts) and gated on its own, in parallel with the
// page (question_gate.ts), so a flagged question drops only itself.
import type { ReadingLevel } from "./reading_levels.ts";
import { withinWordLimit } from "./reading_levels.ts";
import { gentleParentNote, runSafetyGate, type SafetyDeps } from "./safety.ts";
import {
  checkInputSafety,
  firstBlockingVerdict,
  type InputKind,
  type InputSafetyDeps,
  type InputSafetyVerdict,
  type Refusal,
  SAFE_INPUT,
} from "./input_safety.ts";
import { hasForeignScriptText } from "./language_check.ts";
import { namesBrandedCharacter } from "./brand_check.ts";
import { closeWithTheEnd } from "./ending.ts";
import { detectsEndRequest } from "./end_request.ts";
import { isOpeningIdea } from "./opening_idea.ts";
import { gateQuestion } from "./question_gate.ts";
import {
  NO_QUESTION,
  normalizeQuestion,
  type PageChoice,
  type PageQuestion,
  type QuestionKind,
  questionKindFor,
} from "./question_plan.ts";
import { mergeBibleCharacters, stripRepeatedEarlierText, trimToLimit } from "./story_turn.ts";
import type { StoryBible } from "./schemas.ts";
import type { StoryPageModelOutput, StoryPathModelOutput } from "./story_path_schema.ts";

export interface PathPageResponse {
  index: number;
  text: string;
  artPrompt: string;
  /** "" when there's no question (none written, or it failed its own gate). */
  question: string;
  /** Present exactly when `question` isn't "". */
  questionKind?: QuestionKind;
  choices: PageChoice[];
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

type Timings = StoryPathResponseData["timings"];

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

function pageResponse(index: number, text: string, artPrompt: string, isEnding: boolean, question: PageQuestion): PathPageResponse {
  return {
    index,
    text,
    artPrompt,
    question: question.question,
    ...(question.questionKind ? { questionKind: question.questionKind } : {}),
    choices: question.choices,
    isEnding,
  };
}

function noneResponse(
  index: number,
  existingBible: StoryBible,
  timings: Timings,
  parentNote: string = gentleParentNote(),
  refusal: Refusal = "unsafe",
): StoryPathResponseData {
  return {
    action: "none",
    page: pageResponse(index, "", "", false, NO_QUESTION),
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

/** True when the page text or art prompt leaked a foreign-script letter (see language_check.ts). `allowedNames` (R-42) exempts the kid's own name and bible character names. */
function hasForeignScript(pageText: string, artPrompt: string, language: string, allowedNames: string[]): boolean {
  return hasForeignScriptText(pageText, language, allowedNames) || hasForeignScriptText(artPrompt, language, allowedNames);
}

/** What one model attempt puts through the gate: the page itself, plus its already-normalized question. */
interface GateInput {
  pageText: string;
  artPrompt: string;
  /** R-42: bibleTitle and a successful parentNote reach the parent's screen too. */
  extraGateTexts: (string | null)[];
  question: PageQuestion;
  /** Always starts with the kid's own first name. */
  allowedNames: string[];
}

interface GateResult {
  safe: boolean;
  /** The question that may ship with this attempt: unchanged, or NO_QUESTION when it failed its own gate. */
  question: PageQuestion;
  safetyMs: number;
}

async function passesPageGate(input: GateInput, level: ReadingLevel, language: string, safety: SafetyDeps): Promise<boolean> {
  const gateTexts = [input.pageText, input.artPrompt, ...input.extraGateTexts.map((t) => t ?? "")];
  const verdict = await runSafetyGate(gateTexts, level, safety);
  const wordLimitOk = withinWordLimit(input.pageText, level);
  const languageOk = !hasForeignScript(input.pageText, input.artPrompt, language, input.allowedNames);
  const brandOk = !namesBrandedCharacter(gateTexts, input.allowedNames[0]);
  return verdict.safe && wordLimitOk && languageOk && brandOk;
}

/** The page gate and the question's own gate, run in parallel (IMP-25). */
async function gateAttempt(input: GateInput, level: ReadingLevel, language: string, safety: SafetyDeps): Promise<GateResult> {
  const start = performance.now();
  const [safe, gated] = await Promise.all([
    passesPageGate(input, level, language, safety),
    gateQuestion(input.question, level, language, input.allowedNames, safety),
  ]);
  return { safe, question: gated.question, safetyMs: Math.round(performance.now() - start) };
}

function rewriteReasonFor(input: GateInput, level: ReadingLevel, language: string): string {
  if (!withinWordLimit(input.pageText, level)) {
    return "The page was too long for this reading level's word limit.";
  }
  if (hasForeignScript(input.pageText, input.artPrompt, language, input.allowedNames)) {
    return "The page mixed in a word from another language or script. Write it again using only the brief's language.";
  }
  if (namesBrandedCharacter([input.pageText, input.artPrompt], input.allowedNames[0])) {
    return "The page named a branded or famous character. Replace it with an original character of your own.";
  }
  return "The page did not pass the kid-safety rubric.";
}

type WriteOutcome<A> =
  | { attempt: A; question: PageQuestion; timings: Timings }
  | { attempt: null; timings: Timings };

/** Both modes' write loop: one attempt, one rewrite if the page failed its gate, then give up. */
async function writeWithOneRewrite<A extends { modelMs: number }>(
  callModel: (rewriteReason: string | null) => Promise<A>,
  gateInputFor: (attempt: A) => GateInput,
  level: ReadingLevel,
  language: string,
  safety: SafetyDeps,
): Promise<WriteOutcome<A>> {
  const first = await callModel(null);
  const firstInput = gateInputFor(first);
  const firstGate = await gateAttempt(firstInput, level, language, safety);
  if (firstGate.safe) {
    return { attempt: first, question: firstGate.question, timings: { modelMs: first.modelMs, safetyMs: firstGate.safetyMs } };
  }

  const second = await callModel(rewriteReasonFor(firstInput, level, language));
  const secondGate = await gateAttempt(gateInputFor(second), level, language, safety);
  const timings = { modelMs: first.modelMs + second.modelMs, safetyMs: firstGate.safetyMs + secondGate.safetyMs };
  return secondGate.safe ? { attempt: second, question: secondGate.question, timings } : { attempt: null, timings };
}

function inputKindOf(kind: string | undefined): InputKind {
  return kind === "speech" || kind === "choice" ? kind : "typed";
}

/** The brief's free text and this turn's direction, checked together before any model call. */
async function checkInputs(
  input: { text: string; speaker: "parent" | "kid"; kind?: string } | null,
  kidFirstName: string,
  checkBrief: () => Promise<InputSafetyVerdict>,
  inputSafety: InputSafetyDeps | null,
): Promise<InputSafetyVerdict> {
  const direction = input && inputSafety
    ? checkInputSafety(input.text, input.speaker, kidFirstName, inputSafety, inputKindOf(input.kind))
    : Promise.resolve(SAFE_INPUT);
  return firstBlockingVerdict(await Promise.all([checkBrief(), direction]));
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
  /** IMP-24: the brief's own free-text check (brief_safety.ts checkBriefSafety), run before any model call. */
  checkBrief: () => Promise<InputSafetyVerdict>;
}

/**
 * `mode: "path"` (docs/CONTRACTS.md): plans or re-plans the path from `index`
 * onward, then writes page `index`. `input` is null when the brief alone
 * drives the path; at index 0 with no shown pages it's the opening idea
 * (opening_idea.ts); otherwise a direction. Either way it's moderated
 * (together with the brief) before any model call.
 */
export async function runPathTurn(
  readingLevel: ReadingLevel,
  index: number,
  existingBible: StoryBible,
  kidFirstName: string,
  language: string,
  input: { text: string; speaker: "parent" | "kid"; kind?: string } | null,
  deps: RunPathTurnDeps,
  earlierTexts: string[] = [],
): Promise<StoryPathResponseData> {
  const inputVerdict = await checkInputs(input, kidFirstName, deps.checkBrief, deps.inputSafety);
  if (inputVerdict.blocked) {
    return noneResponse(index, existingBible, { modelMs: 0, safetyMs: 0 }, inputVerdict.parentNote ?? gentleParentNote(), inputVerdict.refusal);
  }

  // R-42/ending-eval product rule: a direction that explicitly asks to end
  // the story now (docs/CONTRACTS.md) forces the re-planned path to end at
  // this very page, regardless of what the model returns.
  const forceEnd = input !== null &&
    !isOpeningIdea(index, earlierTexts.length, input.text) &&
    detectsEndRequest(input.text);

  const callModel = async (rewriteReason: string | null): Promise<PathModelAttempt> => {
    const attempt = await deps.callModel(rewriteReason);
    return { ...attempt, output: { ...attempt.output, pageText: preparePageText(attempt.output.pageText, readingLevel, earlierTexts) } };
  };
  const plannedFor = (attempt: PathModelAttempt) => planNewPath(existingBible.path, index, attempt.output.path, forceEnd);

  const gateInputFor = (attempt: PathModelAttempt): GateInput => {
    // The question plan uses the real planned path, so the ending is always talk-only.
    const { path, isEnding } = plannedFor(attempt);
    return {
      pageText: attempt.output.pageText,
      artPrompt: attempt.output.artPrompt,
      extraGateTexts: [attempt.output.bibleTitle, attempt.output.parentNote],
      question: normalizeQuestion(attempt.output.question, questionKindFor(readingLevel, index, path.length), isEnding),
      // R-42: the kid's own name and every known bible character name are never a "foreign script" leak.
      allowedNames: [kidFirstName, ...existingBible.characters.map((c) => c.name), ...attempt.output.bibleCharacters.map((c) => c.name)],
    };
  };

  const outcome = await writeWithOneRewrite(callModel, gateInputFor, readingLevel, language, deps.safety);
  if (outcome.attempt === null) return noneResponse(index, existingBible, outcome.timings);

  const { output } = outcome.attempt;
  const { path, isEnding } = plannedFor(outcome.attempt);
  return {
    action: "page",
    page: pageResponse(index, isEnding ? closeWithTheEnd(output.pageText) : output.pageText, output.artPrompt, isEnding, outcome.question),
    bible: {
      title: output.bibleTitle,
      setting: output.bibleSetting,
      characters: mergeBibleCharacters(existingBible.characters, output.bibleCharacters),
      directions: output.bibleDirections,
      path,
    },
    parentNote: output.parentNote,
    refusal: null,
    timings: outcome.timings,
  };
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
  /** IMP-24: the brief's own free-text check (brief_safety.ts checkBriefSafety), run before any model call. */
  checkBrief: () => Promise<InputSafetyVerdict>;
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
  const briefVerdict = await checkInputs(null, kidFirstName, deps.checkBrief, null);
  if (briefVerdict.blocked) {
    return noneResponse(index, existingBible, { modelMs: 0, safetyMs: 0 }, briefVerdict.parentNote ?? gentleParentNote(), briefVerdict.refusal);
  }

  const isEnding = index === existingBible.path.length - 1;
  const plan = questionKindFor(readingLevel, index, existingBible.path.length);
  // R-42: the kid's own name and every known bible character name are never a "foreign script" leak.
  const allowedNames = [kidFirstName, ...existingBible.characters.map((c) => c.name)];

  const callModel = async (rewriteReason: string | null): Promise<PageModelAttempt> => {
    const attempt = await deps.callModel(rewriteReason);
    return { ...attempt, output: { ...attempt.output, pageText: preparePageText(attempt.output.pageText, readingLevel, earlierTexts) } };
  };
  const gateInputFor = (attempt: PageModelAttempt): GateInput => ({
    pageText: attempt.output.pageText,
    artPrompt: attempt.output.artPrompt,
    extraGateTexts: [attempt.output.parentNote],
    question: normalizeQuestion(attempt.output.question, plan, isEnding),
    allowedNames,
  });

  const outcome = await writeWithOneRewrite(callModel, gateInputFor, readingLevel, language, deps.safety);
  if (outcome.attempt === null) return noneResponse(index, existingBible, outcome.timings);

  const { output } = outcome.attempt;
  return {
    action: "page",
    page: pageResponse(index, isEnding ? closeWithTheEnd(output.pageText) : output.pageText, output.artPrompt, isEnding, outcome.question),
    bible: existingBible,
    parentNote: output.parentNote,
    refusal: null,
    timings: outcome.timings,
  };
}
