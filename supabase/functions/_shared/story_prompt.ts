// Builds the story-turn system prompt from the brief, bible and this turn's
// input (docs/CONTRACTS.md §3 `story-turn`, PRD §7-8.1). A pure function of
// its input so it's fully unit-testable without any model calls.
import { ART_STYLE } from "./art_style.ts";
import { describeReadingLevelForPrompt, type ReadingLevel } from "./reading_levels.ts";
import { KID_SAFETY_RUBRIC } from "./safety_rubric.ts";
import type { Kid, ParentSettings, StoryBible, StoryBrief, StoryInput } from "./schemas.ts";

export interface StoryTurnPromptInput {
  kid: Kid;
  brief: StoryBrief;
  settings: ParentSettings;
  bible: StoryBible;
  pages: { index: number; text: string }[];
  current: { index: number; text: string };
  input: StoryInput;
  /** Set only on a rewrite attempt, after the first pass failed the safety gate. */
  rewriteReason?: string | null;
}

const LANGUAGE_NAMES: Record<string, string> = {
  en: "English",
  es: "Spanish",
  fr: "French",
  de: "German",
  it: "Italian",
  pt: "Portuguese",
  nl: "Dutch",
  sv: "Swedish",
  zh: "Chinese",
  ja: "Japanese",
  ko: "Korean",
  ar: "Arabic",
  hi: "Hindi",
  ru: "Russian",
};

/**
 * A hard language rule for every mode's prompt: observed live, the model can
 * drop a word from another script into the story even when the brief asks
 * for plain English. Paired with the output gate's hasForeignScriptText
 * check (language_check.ts), which catches it if the prompt alone doesn't.
 */
function languageInstruction(languageCode: string): string {
  const name = LANGUAGE_NAMES[languageCode.trim().toLowerCase()] ?? languageCode;
  return `Write every word of the story text, art prompt and reading question only in ${name}. Never mix in a word, phrase or script from any other language.`;
}

function describeBible(bible: StoryBible): string[] {
  const characters = bible.characters.length > 0
    ? bible.characters.map((c) => `${c.name} — ${c.description}`).join("; ")
    : "(none yet)";
  const directions = bible.directions.length > 0
    ? bible.directions.join("; ")
    : "(none yet)";
  return [
    "Story bible so far:",
    `Title: ${bible.title ?? "(none yet)"}`,
    `Setting: ${bible.setting || "(not yet established)"}`,
    `Characters: ${characters}`,
    `Directions so far — each one must keep carrying into every later page: ${directions}`,
  ];
}

const ACTION_GUIDE = [
  "Decide the right action for this turn:",
  '- "append": the input continues the current page. page.text must be the WHOLE current page: every word already on it, unchanged and in order, followed by the new words. If the current page is empty, always use "append".',
  '- "new_page": adding the new words would go over this reading level\'s words-per-page limit, or the current page is clearly finished. page.text is ONLY the next page\'s words and page.index is the current index + 1. Never repeat the current page\'s words.',
  '- "revise_current": the input changes something already on the current page. page.text is the whole rewritten page.',
  '- "none": there is nothing safe or sensible to add right now.',
  'For a "continue" input, write the next small beat of the story yourself, using the same rules.',
].join("\n");

export function buildStoryTurnSystemPrompt(input: StoryTurnPromptInput): string {
  const level = input.kid.readingLevel as ReadingLevel;
  const interests = Array.from(
    new Set([...input.kid.interests, ...input.brief.interests]),
  );

  const lines: string[] = [
    `You are Pop!'s story engine, writing a live picture book with a parent for their child ${input.kid.firstName}.`,
    describeReadingLevelForPrompt(level),
    languageInstruction(input.brief.language),
  ];

  if (interests.length > 0) {
    lines.push(`${input.kid.firstName} loves: ${interests.join(", ")}.`);
  }
  if (input.brief.realMoment) {
    lines.push(
      `This story gently helps with a real moment: ${input.brief.realMoment}. Keep the tone calm and hopeful, and end reassuringly.`,
    );
  }
  if (input.brief.teach) {
    lines.push(`If it fits naturally, let the story help teach: ${input.brief.teach}.`);
  }
  if (input.settings.avoidTopics.length > 0) {
    lines.push(`Never include these topics: ${input.settings.avoidTopics.join(", ")}.`);
  }

  lines.push(
    "Never use surnames, home addresses, school names, or phone numbers anywhere in the story text.",
    KID_SAFETY_RUBRIC,
    `One locked illustration style is used for every picture: ${ART_STYLE}. Write art prompts that fit this style and depict only what is safe to show this child.`,
    ...describeBible(input.bible),
  );

  if (input.pages.length > 0) {
    lines.push("Pages written so far:");
    for (const page of input.pages) {
      lines.push(`Page ${page.index}: ${page.text}`);
    }
  }

  lines.push(
    `Current page ${input.current.index} draft so far: ${input.current.text || "(empty)"}`,
    `This turn's input — kind: ${input.input.kind}, speaker: ${input.input.speaker}: "${input.input.text}"`,
    ACTION_GUIDE,
    "If the input is a direction (an instruction to add or change something, not narration), fold it into the bible's directions so it carries into every later page.",
    'If input.kind is "continue", write the next beat yourself, following the brief and every direction so far.',
    `readingQuestion: one short, warm question a parent can ask ${input.kid.firstName} about this page's words or picture (for example "What colour is the kite?" or "How do you think Maya feels?"), at this reading level and never about ${input.kid.firstName}'s own address, school or family details.`,
    "Respond with only the JSON object the response schema describes.",
  );

  if (input.rewriteReason) {
    lines.push(
      `Your previous attempt at this page was rejected: ${input.rewriteReason} Write it again, gentler and within the word limit, keeping the same action.`,
    );
  }

  return lines.join("\n\n");
}

export interface StoryPathPromptInput {
  kid: Kid;
  brief: StoryBrief;
  settings: ParentSettings;
  bible: StoryBible;
  pages: { index: number; text: string }[];
  index: number;
  /** null at the very start (index 0, no direction yet); a direction otherwise. */
  input: { kind: string; speaker: "parent" | "kid"; text: string } | null;
  /** Set only on a rewrite attempt, after the first pass failed the safety gate. */
  rewriteReason?: string | null;
}

const PATH_PLANNING_GUIDE = [
  "Plan the whole story as a path of about 5 to 8 page beats in total, each one short sentence describing that page's moment.",
  "The path's last beat must clearly end the story: something gentle and reassuring that closes it, never a cliffhanger.",
  "Each page is one still moment that suits a gentle, repeating animation (for example, a dragon that flew into a tree lying knocked out, bobbing gently) — it never itself moves the plot on; the next page does.",
].join("\n");

/** `mode: "path"` (docs/CONTRACTS.md): plans/replans the path from `index` on, then writes page `index`. */
export function buildStoryPathSystemPrompt(input: StoryPathPromptInput): string {
  const level = input.kid.readingLevel as ReadingLevel;
  const interests = Array.from(new Set([...input.kid.interests, ...input.brief.interests]));
  const keptBeats = input.bible.path.slice(0, input.index);

  const lines: string[] = [
    `You are Pop!'s story engine, planning a live picture book's story path for a parent and their child ${input.kid.firstName}.`,
    describeReadingLevelForPrompt(level),
    languageInstruction(input.brief.language),
  ];

  if (interests.length > 0) {
    lines.push(`${input.kid.firstName} loves: ${interests.join(", ")}.`);
  }
  if (input.brief.realMoment) {
    lines.push(
      `This story gently helps with a real moment: ${input.brief.realMoment}. Keep the tone calm and hopeful, and end reassuringly.`,
    );
  }
  if (input.brief.teach) {
    lines.push(`If it fits naturally, let the story help teach: ${input.brief.teach}.`);
  }
  if (input.settings.avoidTopics.length > 0) {
    lines.push(`Never include these topics: ${input.settings.avoidTopics.join(", ")}.`);
  }

  lines.push(
    "Never use surnames, home addresses, school names, or phone numbers anywhere in the story text.",
    KID_SAFETY_RUBRIC,
    `One locked illustration style is used for every picture: ${ART_STYLE}. Write art prompts that fit this style and depict only what is safe to show this child.`,
    ...describeBible(input.bible),
  );

  if (keptBeats.length > 0) {
    lines.push(`Beats already fixed and shown (page 0 to ${input.index - 1}) — never change these, and do not repeat them in your answer:`);
    keptBeats.forEach((beat, i) => lines.push(`Page ${i}: ${beat}`));
  }
  if (input.pages.length > 0) {
    lines.push("Pages already written and shown:");
    for (const page of input.pages) lines.push(`Page ${page.index}: ${page.text}`);
  }

  lines.push(PATH_PLANNING_GUIDE);

  if (input.input && input.input.text.trim() !== "") {
    lines.push(
      `A direction just came in — kind: ${input.input.kind}, speaker: ${input.input.speaker}: "${input.input.text}"`,
      `Fold this direction into the bible's directions so it carries into every later page, and re-plan the path from page ${input.index} on. The ending may change, but the path must still reach one.`,
    );
  } else {
    lines.push("Plan the path from the brief above.");
  }

  lines.push(
    `Return only the beats for page ${input.index} onward as "path" (never the beats already fixed above), plus "isEnding": true only if page ${input.index} is the last beat of the full path.`,
    `Then write page ${input.index} itself: "pageText" at this reading level, "artPrompt" for its picture, and "readingQuestion": one short, warm question a parent can ask ${input.kid.firstName} about this page's words or picture, never about ${input.kid.firstName}'s own address, school or family details.`,
    "Respond with only the JSON object the response schema describes.",
  );

  if (input.rewriteReason) {
    lines.push(
      `Your previous attempt at this page was rejected: ${input.rewriteReason} Write it again, gentler and within the word limit, keeping the same path.`,
    );
  }

  return lines.join("\n\n");
}

export interface StoryPagePromptInput {
  kid: Kid;
  brief: StoryBrief;
  settings: ParentSettings;
  bible: StoryBible;
  pages: { index: number; text: string }[];
  index: number;
  /** Set only on a rewrite attempt, after the first pass failed the safety gate. */
  rewriteReason?: string | null;
}

/** `mode: "page"` (docs/CONTRACTS.md): writes page `index` from `bible.path[index]`, with no re-planning. */
export function buildStoryPageSystemPrompt(input: StoryPagePromptInput): string {
  const level = input.kid.readingLevel as ReadingLevel;
  const beat = input.bible.path[input.index] ?? "";

  const lines: string[] = [
    `You are Pop!'s story engine, writing one page of a live picture book for ${input.kid.firstName}.`,
    describeReadingLevelForPrompt(level),
    languageInstruction(input.brief.language),
    "Never use surnames, home addresses, school names, or phone numbers anywhere in the story text.",
    KID_SAFETY_RUBRIC,
    `One locked illustration style is used for every picture: ${ART_STYLE}. Write an art prompt that fits this style and depicts only what is safe to show this child.`,
    ...describeBible(input.bible),
  ];

  if (input.pages.length > 0) {
    lines.push("Pages already written and shown:");
    for (const page of input.pages) lines.push(`Page ${page.index}: ${page.text}`);
  }

  lines.push(
    `This page's planned beat: ${beat}`,
    "Write only this page from that beat — do not invent a different moment or change the story path. Never retell an earlier page's words.",
    "This page is one still moment that suits a gentle, repeating animation; it never itself moves the plot on.",
    `Write: "pageText" at this reading level, "artPrompt" for its picture, and "readingQuestion": one short, warm question a parent can ask ${input.kid.firstName} about this page's words or picture, never about ${input.kid.firstName}'s own address, school or family details.`,
    "Respond with only the JSON object the response schema describes.",
  );

  if (input.rewriteReason) {
    lines.push(
      `Your previous attempt at this page was rejected: ${input.rewriteReason} Write it again, gentler and within the word limit.`,
    );
  }

  return lines.join("\n\n");
}

export function buildTitlePrompt(
  bible: StoryBible,
  pages: { index: number; text: string }[],
  firstName: string,
): string {
  const storyText = [...pages]
    .sort((a, b) => a.index - b.index)
    .map((p) => p.text)
    .join("\n");
  return [
    `Write a short, warm, child-friendly title (4-8 words, no subtitle, no quotation marks) for this picture book, made for ${firstName}.`,
    `Setting: ${bible.setting}`,
    `Story so far:\n${storyText}`,
    'Respond with only JSON: {"title": string}.',
  ].join("\n\n");
}
