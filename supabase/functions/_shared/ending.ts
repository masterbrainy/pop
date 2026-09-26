// The story's last page always closes with "The end." (S14): the model is asked
// to write a clear close, but doesn't always, and a picture book's last words
// should leave no doubt. The page's own words are never cut to make room, so
// the ending page may run two words over the reading level's limit (R-45).

const THE_END = "The end.";
const ALREADY_CLOSED = /\bthe end[.!]*\s*$/i;

export function closeWithTheEnd(text: string): string {
  const trimmed = text.trim();
  if (ALREADY_CLOSED.test(trimmed)) return trimmed;
  const sentence = /[.!?]["'”’)]*$/.test(trimmed) ? trimmed : `${trimmed.replace(/[,;:]$/, "")}.`;
  return `${sentence} ${THE_END}`;
}
