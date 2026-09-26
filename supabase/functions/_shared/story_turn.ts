// `story-turn`'s own turn orchestration (docs/CONTRACTS.md §3, PRD §8.6 K1):
// call the model, run it past the kid-safety gate and the reading level's
// word limit, rewrite once on failure, and fall back to action "none" with a
// gentle parentNote. Deps are injected (as safety.ts does) so this is fully
// unit-testable without any network call.
import type { ReadingLevel } from "./reading_levels.ts";
import { withinWordLimit } from "./reading_levels.ts";
import { gentleParentNote, runSafetyGate, type SafetyDeps } from "./safety.ts";
import { checkInputSafety, type InputSafetyDeps } from "./input_safety.ts";
import type { Character, StoryBible } from "./schemas.ts";
import type { StoryModelOutput } from "./story_schema.ts";

export interface StoryPageResponse {
  index: number;
  text: string;
  artPrompt: string;
  breakSuggested: boolean;
  /** One question to ask about the page (PRD C3); empty when there's none. */
  question: string;
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

// `turn` (and `title`, via the shared bible schema) don't plan or touch the
// story path (P-04) — only `path` mode replans it and `page` mode reads it —
// so the existing bible's path always comes back unchanged here.
function bibleFromOutput(output: StoryModelOutput, existingBible: StoryBible): StoryBible {
  return {
    title: output.bibleTitle,
    setting: output.bibleSetting,
    characters: mergeBibleCharacters(existingBible.characters, output.bibleCharacters),
    directions: output.bibleDirections,
    path: existingBible.path,
  };
}

function toResponseData(
  output: StoryModelOutput,
  pageIndex: number,
  existingBible: StoryBible,
  timings: { modelMs: number; safetyMs: number },
): StoryTurnResponseData {
  return {
    action: output.action,
    page: {
      index: output.action === "new_page" ? pageIndex + 1 : pageIndex,
      text: output.pageText,
      artPrompt: output.artPrompt,
      breakSuggested: output.breakSuggested,
      question: output.readingQuestion.trim(),
    },
    bible: bibleFromOutput(output, existingBible),
    parentNote: output.parentNote,
    timings,
  };
}

/**
 * An "append" returns the whole page. If the model sent only the new words, put the
 * page's existing words back in front, so nothing already told disappears.
 */
export function keepExistingWords(output: StoryModelOutput, currentText: string): StoryModelOutput {
  const existing = currentText.trim();
  if (output.action !== "append" || existing === "") return output;
  const squash = (text: string) => text.replace(/\s+/g, " ").trim().toLowerCase();
  if (squash(output.pageText).startsWith(squash(existing))) return output;
  return { ...output, pageText: `${existing} ${output.pageText.trim()}` };
}

/**
 * Keeps a safe page within the reading level's word limit without refusing it. A safe
 * addition that overflows a full page moves onto a new page with only the new words; any
 * other overlong page is cut to whole sentences (or, for one long sentence, to the limit).
 */
export function fitToPage(output: StoryModelOutput, currentText: string, level: ReadingLevel): StoryModelOutput {
  if (output.action === "none" || withinWordLimit(output.pageText, level)) return output;
  const existing = currentText.trim().split(/\s+/).filter(Boolean);
  const words = output.pageText.trim().split(/\s+/).filter(Boolean);
  if (output.action === "append" && existing.length > 0 && words.length > existing.length) {
    const added = words.slice(existing.length).join(" ");
    return { ...output, action: "new_page", pageText: trimToLimit(added, level) };
  }
  return { ...output, pageText: trimToLimit(output.pageText, level) };
}

export function trimToLimit(text: string, level: ReadingLevel): string {
  if (withinWordLimit(text, level)) return text.trim();
  const sentences = text.trim().split(/(?<=[.!?])\s+/);
  let kept = "";
  for (const sentence of sentences) {
    const candidate = kept ? `${kept} ${sentence}` : sentence;
    if (!withinWordLimit(candidate, level)) break;
    kept = candidate;
  }
  if (kept) return kept;
  const words = text.trim().split(/\s+/);
  let cut = words.length;
  while (cut > 1 && !withinWordLimit(words.slice(0, cut).join(" "), level)) cut -= 1;
  return `${words.slice(0, cut).join(" ").replace(/[,;:]$/, "")}.`.replace(/([.!?])\.$/, "$1");
}

/**
 * The model sometimes starts a page by retelling the pages before it. Strip earlier pages'
 * words from the front of the new text (in order, ignoring case, spacing and punctuation),
 * unless that would leave the page empty. Shared by every mode's output gate (turn, path, page).
 */
export function stripRepeatedEarlierText(pageText: string, earlierTexts: string[]): string {
  const words = pageText.trim().split(/\s+/).filter(Boolean);
  const bare = (word: string) => word.toLowerCase().replace(/[^\p{L}\p{N}']/gu, "");
  let start = 0;
  for (const earlier of earlierTexts) {
    const earlierWords = earlier.trim().split(/\s+/).filter(Boolean).map(bare);
    if (earlierWords.length === 0) continue;
    const next = words.slice(start, start + earlierWords.length).map(bare);
    if (next.length === earlierWords.length && next.every((word, i) => word === earlierWords[i])) {
      start += earlierWords.length;
    }
  }
  if (start === 0 || start >= words.length) return pageText;
  return words.slice(start).join(" ");
}

export function dropRepeatedEarlierText(output: StoryModelOutput, earlierTexts: string[]): StoryModelOutput {
  if (output.action === "none") return output;
  return { ...output, pageText: stripRepeatedEarlierText(output.pageText, earlierTexts) };
}

/**
 * The safe fallback when even the rewrite fails the gate (PRD §8.6 responses),
 * or when the input itself was blocked before any model call (R-37). `parentNote`
 * defaults to the generic gentle redirect; a blocked input passes its own note.
 */
function noneResponse(
  currentIndex: number,
  currentText: string,
  existingBible: StoryBible,
  timings: { modelMs: number; safetyMs: number },
  parentNote: string = gentleParentNote(),
): StoryTurnResponseData {
  return {
    action: "none",
    page: { index: currentIndex, text: currentText, artPrompt: "", breakSuggested: false, question: "" },
    bible: existingBible,
    parentNote,
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
    return { safe: true, safetyMs: Math.round(performance.now() - start) };
  }
  const verdict = await runSafetyGate([output.pageText, output.artPrompt, output.readingQuestion], readingLevel, safety);
  const wordLimitOk = withinWordLimit(output.pageText, readingLevel);
  return { safe: verdict.safe && wordLimitOk, safetyMs: Math.round(performance.now() - start) };
}

export async function runStoryTurn(
  readingLevel: ReadingLevel,
  currentIndex: number,
  currentText: string,
  existingBible: StoryBible,
  deps: StoryTurnDeps,
  earlierTexts: string[] = [],
): Promise<StoryTurnResponseData> {
  const keepPage = (attempt: ModelAttempt): ModelAttempt => ({
    ...attempt,
    output: fitToPage(keepExistingWords(dropRepeatedEarlierText(attempt.output, earlierTexts), currentText), currentText, readingLevel),
  });
  const first = keepPage(await deps.callModel(null));
  const firstGate = await passesGate(first.output, readingLevel, deps.safety);
  if (firstGate.safe) {
    return toResponseData(first.output, currentIndex, existingBible, {
      modelMs: first.modelMs,
      safetyMs: firstGate.safetyMs,
    });
  }

  const rewriteReason = !withinWordLimit(first.output.pageText, readingLevel)
    ? "The page was too long for this reading level's word limit."
    : "The page did not pass the kid-safety rubric.";
  const second = keepPage(await deps.callModel(rewriteReason));
  const secondGate = await passesGate(second.output, readingLevel, deps.safety);
  const modelMs = first.modelMs + second.modelMs;
  const safetyMs = firstGate.safetyMs + secondGate.safetyMs;

  if (secondGate.safe) {
    return toResponseData(second.output, currentIndex, existingBible, {
      modelMs,
      safetyMs,
    });
  }

  return noneResponse(currentIndex, currentText, existingBible, { modelMs, safetyMs });
}

export interface StoryTurnDepsWithInputSafety extends StoryTurnDeps {
  inputSafety: InputSafetyDeps;
}

/**
 * Wraps `runStoryTurn` with the input-safety check (R-37, PRD §8.6): moderates
 * `input.text` (plus, for a kid speaker, the cheap real-harm rubric) before any
 * model call. A blocked input never reaches the model and comes back as
 * `action: "none"` with the input check's own calm `parentNote`.
 */
export async function runStoryTurnWithInputGate(
  readingLevel: ReadingLevel,
  currentIndex: number,
  currentText: string,
  existingBible: StoryBible,
  input: { text: string; speaker: "parent" | "kid" },
  kidFirstName: string,
  deps: StoryTurnDepsWithInputSafety,
  earlierTexts: string[] = [],
): Promise<StoryTurnResponseData> {
  const verdict = await checkInputSafety(input.text, input.speaker, kidFirstName, deps.inputSafety);
  if (verdict.blocked) {
    return noneResponse(currentIndex, currentText, existingBible, { modelMs: 0, safetyMs: 0 }, verdict.parentNote ?? gentleParentNote());
  }
  return runStoryTurn(readingLevel, currentIndex, currentText, existingBible, deps, earlierTexts);
}
