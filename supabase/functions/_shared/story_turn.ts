// `story-turn`'s own turn orchestration (docs/CONTRACTS.md §3, PRD §8.6 K1):
// call the model, run it past the kid-safety gate and the reading level's
// word limit, rewrite once on failure, and fall back to action "none" with a
// gentle parentNote. Deps are injected (as safety.ts does) so this is fully
// unit-testable without any network call.
import type { ReadingLevel } from "./reading_levels.ts";
import { withinWordLimit } from "./reading_levels.ts";
import { gentleParentNote, runSafetyGate, type SafetyDeps } from "./safety.ts";
import type { Character, StoryBible } from "./schemas.ts";
import type { StoryModelOutput } from "./story_schema.ts";

export interface StoryPageResponse {
  index: number;
  text: string;
  artPrompt: string;
  breakSuggested: boolean;
}

export interface StoryTurnResponseData {
  action: StoryModelOutput["action"];
  page: StoryPageResponse;
  bible: StoryBible;
  parentNote: string | null;
  timings: { modelMs: number; safetyMs: number };
}

export interface ModelAttempt {
  output: StoryModelOutput;
  modelMs: number;
}

export interface StoryTurnDeps {
  /** rewriteReason is null for the first attempt, else why the last attempt failed. */
  callModel: (rewriteReason: string | null) => Promise<ModelAttempt>;
  safety: SafetyDeps;
}

/**
 * Keeps each character's existing `referencePath` (the model never invents
 * one — that's set only once the `art` function has generated its reference
 * sheet) by matching on id; new characters get `null`.
 */
export function mergeBibleCharacters(
  existing: Character[],
  updated: { id: string; name: string; description: string }[],
): Character[] {
  const existingById = new Map(existing.map((c) => [c.id, c]));
  return updated.map((u) => ({
    id: u.id,
    name: u.name,
    description: u.description,
    referencePath: existingById.get(u.id)?.referencePath ?? null,
  }));
}

function bibleFromOutput(output: StoryModelOutput, existingCharacters: Character[]): StoryBible {
  return {
    title: output.bibleTitle,
    setting: output.bibleSetting,
    characters: mergeBibleCharacters(existingCharacters, output.bibleCharacters),
    directions: output.bibleDirections,
  };
}

function toResponseData(
  output: StoryModelOutput,
  pageIndex: number,
  existingCharacters: Character[],
  timings: { modelMs: number; safetyMs: number },
): StoryTurnResponseData {
  return {
    action: output.action,
    page: {
      index: pageIndex,
      text: output.pageText,
      artPrompt: output.artPrompt,
      breakSuggested: output.breakSuggested,
    },
    bible: bibleFromOutput(output, existingCharacters),
    parentNote: output.parentNote,
    timings,
  };
}

/** The safe fallback when even the rewrite fails the gate (PRD §8.6 responses). */
function noneResponse(
  currentIndex: number,
  currentText: string,
  existingBible: StoryBible,
  timings: { modelMs: number; safetyMs: number },
): StoryTurnResponseData {
  return {
    action: "none",
    page: { index: currentIndex, text: currentText, artPrompt: "", breakSuggested: false },
    bible: existingBible,
    parentNote: gentleParentNote(),
    timings,
  };
}

async function passesGate(
  output: StoryModelOutput,
  readingLevel: ReadingLevel,
  safety: SafetyDeps,
): Promise<{ safe: boolean; safetyMs: number }> {
  const start = performance.now();
  if (output.action === "none") {
    // Nothing new to check; the model already decided not to add anything.
    return { safe: true, safetyMs: performance.now() - start };
  }
  const verdict = await runSafetyGate([output.pageText, output.artPrompt], readingLevel, safety);
  const wordLimitOk = withinWordLimit(output.pageText, readingLevel);
  return { safe: verdict.safe && wordLimitOk, safetyMs: performance.now() - start };
}

export async function runStoryTurn(
  readingLevel: ReadingLevel,
  currentIndex: number,
  currentText: string,
  existingBible: StoryBible,
  deps: StoryTurnDeps,
): Promise<StoryTurnResponseData> {
  const first = await deps.callModel(null);
  const firstGate = await passesGate(first.output, readingLevel, deps.safety);
  if (firstGate.safe) {
    return toResponseData(first.output, currentIndex, existingBible.characters, {
      modelMs: first.modelMs,
      safetyMs: firstGate.safetyMs,
    });
  }

  const rewriteReason = !withinWordLimit(first.output.pageText, readingLevel)
    ? "The page was too long for this reading level's word limit."
    : "The page did not pass the kid-safety rubric.";
  const second = await deps.callModel(rewriteReason);
  const secondGate = await passesGate(second.output, readingLevel, deps.safety);
  const modelMs = first.modelMs + second.modelMs;
  const safetyMs = firstGate.safetyMs + secondGate.safetyMs;

  if (secondGate.safe) {
    return toResponseData(second.output, currentIndex, existingBible.characters, {
      modelMs,
      safetyMs,
    });
  }

  return noneResponse(currentIndex, currentText, existingBible, { modelMs, safetyMs });
}
