// Reading-level limits (PRD §8.7), kept byte-consistent with
// PopKit/Sources/PopKit/Domain/ReadingLevel.swift so the app and server agree.

export type ReadingLevel = "listener" | "early_reader" | "reader";

export const READING_LEVELS: readonly ReadingLevel[] = [
  "listener",
  "early_reader",
  "reader",
];

export interface ReadingLevelLimits {
  readonly ages: string;
  readonly maxWords: number;
  readonly minSentences: number;
  readonly maxSentences: number;
}

const LIMITS: Record<ReadingLevel, ReadingLevelLimits> = {
  listener: { ages: "3-4", maxWords: 15, minSentences: 1, maxSentences: 2 },
  early_reader: { ages: "5-6", maxWords: 30, minSentences: 2, maxSentences: 3 },
  reader: { ages: "7-8", maxWords: 60, minSentences: 1, maxSentences: 5 },
};

export function isReadingLevel(value: string): value is ReadingLevel {
  return (READING_LEVELS as readonly string[]).includes(value);
}

export function readingLevelLimits(level: ReadingLevel): ReadingLevelLimits {
  return LIMITS[level];
}

/** A short instruction for the story-engine system prompt. */
export function describeReadingLevelForPrompt(level: ReadingLevel): string {
  const l = LIMITS[level];
  const sentenceSpan = l.minSentences === l.maxSentences
    ? `${l.minSentences} sentence${l.minSentences > 1 ? "s" : ""}`
    : `${l.minSentences}-${l.maxSentences} sentences`;
  return `Ages ${l.ages}. Each page must have ${sentenceSpan} and use at most ${l.maxWords} words total. Use very simple, concrete vocabulary a child this age knows.`;
}

/** A rough word count for validating model output against the level's limit. */
export function countWords(text: string): number {
  const trimmed = text.trim();
  if (trimmed.length === 0) return 0;
  return trimmed.split(/\s+/).length;
}

export function withinWordLimit(text: string, level: ReadingLevel): boolean {
  return countWords(text) <= LIMITS[level].maxWords;
}
