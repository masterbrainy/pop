// The app never plans page 1 from the brief alone: page 1 is written only once
// the parent (or kid) speaks or types the first prompt, sent as a `path` call
// at index 0 with no shown pages and `input` set. That input is the story's
// opening idea, not a mid-story direction: it plans the whole path, and an
// ending it describes ("…and we end the story with a bedtime hug") is how the
// story should close, never a request to stop on page 1. Shared by the path
// prompt (story_prompt.ts) and the forced-ending rule (story_path.ts).

/** True for the first prompt of a story: page 0, nothing shown yet, and some text. */
export function isOpeningIdea(index: number, shownPageCount: number, inputText: string | null | undefined): boolean {
  return index === 0 && shownPageCount === 0 && (inputText ?? "").trim() !== "";
}
