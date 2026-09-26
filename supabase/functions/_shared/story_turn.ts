// Shared page-text helpers used by story-turn's `path` and `page` modes
// (docs/CONTRACTS.md "story-turn modes path and page", P-04): keeping a
// bible's characters stable across turns, trimming an overlong page to the
// reading level's word limit, and stripping a page that retells earlier
// pages. Pure functions, fully unit-testable without any network call.
//
// `mode: "turn"` (the pre-P-04 append/new_page/revise_current engine) used to
// live here too; it was removed once the app moved to the story path and the
// eval passed on `path`/`page` (docs/CONTRACTS.md §3, R-37/R-41 follow-up).
import type { ReadingLevel } from "./reading_levels.ts";
import { withinWordLimit } from "./reading_levels.ts";
import type { Character } from "./schemas.ts";

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

/**
 * Keeps a safe page within the reading level's word limit without refusing
 * it: cut to whole sentences, or for one long sentence, to the word limit.
 */
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
 * unless that would leave the page empty. Shared by every mode's output gate (path, page).
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
