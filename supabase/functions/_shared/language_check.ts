// Foreign-script leak guard for the story-turn output gate: observed live
// (simulator run against the deployed "path" mode), the model sometimes drops
// a word from another script into an "en" story ("...A friendly fox is рядом,
// and both look surprised."). Digits, punctuation and emoji are never
// letters, so they're unaffected; only a Letter (`\p{L}`) outside Latin
// script counts as a leak. Only "en" is checked today — every other language
// passes through unchecked until it's properly supported (PRD language is a
// stretch feature), so this never blocks a legitimately non-English story.
const LATIN_LETTER = /\p{Script=Latin}/u;
const ANY_LETTER = /\p{L}/u;

/** True when `text` contains a letter outside Latin script, for an "en" brief. */
export function hasForeignScriptText(text: string, language: string): boolean {
  if (language.trim().toLowerCase() !== "en") return false;
  for (const ch of text) {
    if (ANY_LETTER.test(ch) && !LATIN_LETTER.test(ch)) return true;
  }
  return false;
}
