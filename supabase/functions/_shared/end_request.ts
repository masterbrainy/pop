// Detects a direction that explicitly asks the story to end right now
// (docs/CONTRACTS.md "story-turn modes path and page"): "the end", "let's
// finish the story here with a proper ending", "wrap up the story now", and
// similar phrasings. Used by both the path prompt (story_prompt.ts, to
// instruct the model) and the path-length clamp (story_path.ts's
// planNewPath, to guarantee the rule regardless of the model's compliance).
const END_REQUEST_PATTERNS: RegExp[] = [
  /\bthe end\b/i,
  /\bends? (?:the|this|our) story\b/i,
  /\bending (?:the|this|our) story\b/i,
  /\bfinish(?:es|ed|ing)? (?:the|this|our) story\b/i,
  /\bwrap(?:s|ped|ping)? up (?:the|this|our) story\b/i,
  /\bstop (?:the|this|our) story (?:now|here)\b/i,
];

/** True when `text` (a parent or kid direction) explicitly asks to end the story now. */
export function detectsEndRequest(text: string): boolean {
  const trimmed = text.trim();
  if (trimmed === "") return false;
  return END_REQUEST_PATTERNS.some((pattern) => pattern.test(trimmed));
}
