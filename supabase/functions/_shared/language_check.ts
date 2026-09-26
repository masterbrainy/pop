// Foreign-script leak guard for the story-turn output gate: observed live
// (simulator run against the deployed "path" mode), the model sometimes drops
// a word from another script into an "en" story ("...A friendly fox is рядом,
// and both look surprised."). Digits, punctuation and emoji are never
// letters, so they're unaffected; only a Letter (`\p{L}`) outside Latin (or a
// shared, script-neutral) script counts as a leak. Only "en" is checked
// today — every other language passes through unchecked until it's properly
// supported (PRD language is a stretch feature), so this never blocks a
// legitimately non-English story.
const LATIN_OR_SHARED_LETTER = /\p{Script=Latin}|\p{Script=Common}|\p{Script=Inherited}/u;
const ANY_LETTER = /\p{L}/u;

/**
 * Removes every case-insensitive occurrence of each name from `text` before
 * the script scan (R-42): a kid's own name, or a bible character's name, is
 * never a "foreign script leak" even when it's written in a non-Latin script
 * (for example 李明 or Дима) — it's the name the parent chose, not a mixed-in
 * word from another language.
 */
function stripAllowedNames(text: string, allowedNames: string[]): string {
  let stripped = text;
  for (const name of allowedNames) {
    const trimmed = name.trim();
    if (trimmed.length === 0) continue;
    const escaped = trimmed.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    stripped = stripped.replace(new RegExp(escaped, "gui"), "");
  }
  return stripped;
}

/**
 * True when `text` contains a letter outside Latin (and shared/script-neutral)
 * script, for an "en" brief. `allowedNames` (the kid's first name and any
 * bible character names) are stripped before the scan (R-42).
 *
 * A letter counts as a leak only when its own Unicode script is something
 * else identifiable (Cyrillic, Han, Arabic, ...). Many ordinary punctuation
 * and modifier characters a model can emit for stylistic reasons — for
 * example U+02BC MODIFIER LETTER APOSTROPHE used in place of a straight or
 * curly apostrophe — are categorized as letters (`\p{L}`) but belong to the
 * "Common" script shared across all scripts, so they must never trip this
 * check on their own.
 */
export function hasForeignScriptText(text: string, language: string, allowedNames: string[] = []): boolean {
  if (language.trim().toLowerCase() !== "en") return false;
  const stripped = stripAllowedNames(text, allowedNames);
  for (const ch of stripped) {
    if (ANY_LETTER.test(ch) && !LATIN_OR_SHARED_LETTER.test(ch)) return true;
  }
  return false;
}
