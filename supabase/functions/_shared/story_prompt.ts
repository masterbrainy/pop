// Builds story-turn's `path`/`page`/title system prompts from the brief,
// bible and (for `path`) this turn's direction (docs/CONTRACTS.md "story-turn
// modes path and page", PRD §7-8.1). Pure functions of their input so they're
// fully unit-testable without any model calls.
//
// `mode: "turn"`'s prompt builder (append/new_page/revise_current) lived here
// too; it was removed with `mode: "turn"` once the app moved to the story
// path and the eval passed on `path`/`page`.
import { ART_STYLE } from "./art_style.ts";
import { brandedCharactersIn } from "./brand_check.ts";
import { detectsEndRequest } from "./end_request.ts";
import { isOpeningIdea } from "./opening_idea.ts";
import { describeReadingLevelForPrompt, type ReadingLevel } from "./reading_levels.ts";
import { KID_SAFETY_RUBRIC } from "./safety_rubric.ts";
import type { Kid, ParentSettings, StoryBible, StoryBrief } from "./schemas.ts";

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

export interface StoryPathPromptInput {
  kid: Kid;
  brief: StoryBrief;
  settings: ParentSettings;
  bible: StoryBible;
  pages: { index: number; text: string }[];
  index: number;
  /** null for a brief-only plan; the opening idea at index 0 with no shown pages (opening_idea.ts); a direction otherwise. */
  input: { kind: string; speaker: "parent" | "kid"; text: string } | null;
  /** Set only on a rewrite attempt, after the first pass failed the safety gate. */
  rewriteReason?: string | null;
}

/**
 * Shared with buildStoryPageSystemPrompt's own isEnding line: concrete
 * closing images the model can land on, so the path's actual last page reads
 * like a definite ending rather than just trailing off mid-scene (R-35 d,
 * R-42 ending-eval). Written to read naturally regardless of time of day —
 * "safe and happy" and "settling down together" fit a daytime adventure as
 * well as a bedtime story.
 */
const ENDING_PAGE_IMAGES =
  "for example the characters ending up safe and happy, heading home, settling down together, or drifting off to sleep";

/**
 * Prescriptive close instruction for the exact page already known to be the
 * path's last one (R-42/ending-eval): rather than widening the eval's
 * checkReachesEnding heuristic to match whatever the model happens to write,
 * the model is told to land its last sentence on one of the exact phrases
 * that heuristic recognizes, or simply end with the words "The end." — a
 * reliable, unmistakable close regardless of reading level or time-of-day
 * setting (a daytime treasure hunt can still end "safe and back home").
 */
function endingCloseInstruction(level: ReadingLevel): string {
  const closingPhrases =
    '"lived happily ever after," "safe and back home," "snuggled up," "fell asleep," or "drifted off to sleep"';
  if (level === "reader") {
    return `This page is the path's last page: make its very last sentence a clear, unmistakable close by ending it with one of these exact phrases — ${closingPhrases} — or simply the words "The end." Never leave the last sentence open or unresolved.`;
  }
  return `This page is the path's last page: make its very last sentence a clear, unmistakable close, for example everyone safe and happy, snuggled up, or fast asleep, and it may simply end with the words "The end." Never leave the last sentence open or unresolved.`;
}

/**
 * `art` draws (and sends reference images for) only the bible characters a
 * page's artPrompt names (art_request.ts charactersIn), so the art prompt has
 * to name each character on the page exactly as the bible does, and no others.
 */
const ART_PROMPT_NAMES_INSTRUCTION =
  "In artPrompt, name every character who appears by their bible name, and only those.";

const PATH_PLANNING_GUIDE = [
  "Plan the whole story as a path of about 5 to 8 page beats in total, each one short sentence describing that page's moment.",
  `The path's last beat must clearly end the story — ${ENDING_PAGE_IMAGES} — something gentle and reassuring that closes it, never a cliffhanger.`,
  "Each page is one still moment that suits a gentle, repeating animation (for example, a dragon that flew into a tree lying knocked out, bobbing gently) — it never itself moves the plot on; the next page does.",
].join("\n");

/**
 * Names a brand or famous character the brief, the bible or a direction brought in, so the
 * model swaps it for an original one up front: the output gate refuses those names, and a
 * kid who loves Lego would otherwise have every page refused (R-44).
 */
function brandInstruction(texts: string[], kidFirstName: string): string[] {
  const names = Array.from(new Set(texts.flatMap((text) => brandedCharactersIn(text, kidFirstName))));
  if (names.length === 0) return [];
  return [
    `Never use these brand or character names: ${names.join(", ")}. Turn each into something original of your own (for example, colourful building bricks, or an ice princess you invent), never the brand itself.`,
  ];
}

function bibleTexts(bible: StoryBible): string[] {
  return [bible.title ?? "", bible.setting, ...bible.directions, ...bible.path, ...bible.characters.map((c) => `${c.name} ${c.description}`)];
}

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
  lines.push(...brandInstruction(
    [...interests, input.brief.realMoment ?? "", input.brief.teach ?? "", input.input?.text ?? "", ...bibleTexts(input.bible)],
    input.kid.firstName,
  ));

  lines.push(
    "Never use surnames, home addresses, school names, or phone numbers anywhere in the story text.",
    KID_SAFETY_RUBRIC,
    `One locked illustration style is used for every picture: ${ART_STYLE}. Write art prompts that fit this style and depict only what is safe to show this child.`,
    ART_PROMPT_NAMES_INSTRUCTION,
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

  if (input.input && isOpeningIdea(input.index, input.pages.length, input.input.text)) {
    const whose = input.input.speaker === "kid" ? `${input.kid.firstName}'s` : "The parent's";
    lines.push(
      `${whose} opening idea for the story: "${input.input.text}". Plan the whole path from it, with the brief as background.`,
      "Fold this opening idea into the bible's directions so it carries into every later page.",
    );
  } else if (input.input && input.input.text.trim() !== "") {
    lines.push(
      `A direction just came in — kind: ${input.input.kind}, speaker: ${input.input.speaker}: "${input.input.text}"`,
      `Fold this direction into the bible's directions so it carries into every later page, and re-plan the path from page ${input.index} on. The ending may change, but the path must still reach one.`,
    );
    if (detectsEndRequest(input.input.text)) {
      lines.push(
        `This direction asks to end the story right now: make page ${input.index} the very last beat of the re-planned path — do not plan any beats after it, even though that's fewer than the usual 5 to 8 — and set "isEnding" to true.`,
        endingCloseInstruction(level),
      );
    }
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
  const isEnding = input.bible.path.length > 0 && input.index === input.bible.path.length - 1;

  const lines: string[] = [
    `You are Pop!'s story engine, writing one page of a live picture book for ${input.kid.firstName}.`,
    describeReadingLevelForPrompt(level),
    languageInstruction(input.brief.language),
    "Never use surnames, home addresses, school names, or phone numbers anywhere in the story text.",
    KID_SAFETY_RUBRIC,
    `One locked illustration style is used for every picture: ${ART_STYLE}. Write an art prompt that fits this style and depicts only what is safe to show this child.`,
    ART_PROMPT_NAMES_INSTRUCTION,
    ...describeBible(input.bible),
    ...brandInstruction([...input.kid.interests, ...input.brief.interests, ...bibleTexts(input.bible)], input.kid.firstName),
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

  if (isEnding) {
    lines.push(endingCloseInstruction(level));
  }

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
