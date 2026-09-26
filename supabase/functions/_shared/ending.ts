// The story's last page always closes with "The end." (S14): the model is asked
// to write a clear close, but doesn't always, and a picture book's last words
// should leave no doubt. Kept within the reading level's word limit by dropping
// trailing sentences (or, for one long sentence, words) to make room.
import { type ReadingLevel, withinWordLimit } from "./reading_levels.ts";

const THE_END = "The end.";
const ALREADY_CLOSED = /\bthe end[.!]*\s*$/i;

export function closeWithTheEnd(text: string, level: ReadingLevel): string {
  const trimmed = text.trim();
  if (ALREADY_CLOSED.test(trimmed)) return trimmed;
  const fits = (body: string) => withinWordLimit(`${body} ${THE_END}`, level);
  if (fits(trimmed)) return `${trimmed} ${THE_END}`;

  const sentences = trimmed.split(/(?<=[.!?])\s+/);
  for (let count = sentences.length - 1; count >= 1; count--) {
    const kept = sentences.slice(0, count).join(" ");
    if (fits(kept)) return `${kept} ${THE_END}`;
  }
  const words = trimmed.split(/\s+/);
  let cut = words.length;
  while (cut > 1 && !fits(`${words.slice(0, cut).join(" ")}.`)) cut -= 1;
  const body = `${words.slice(0, cut).join(" ").replace(/[,;:]$/, "")}.`.replace(/([.!?])\.$/, "$1");
  return `${body} ${THE_END}`;
}
