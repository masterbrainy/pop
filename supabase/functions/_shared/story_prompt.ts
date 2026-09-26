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
  '- "append": the input continues the current page\'s words.',
  '- "new_page": the current page is full or done, so write the next page\'s draft.',
  '- "revise_current": the input changes something already on the current page.',
  '- "none": there is nothing safe or sensible to add right now.',
].join("\n");

export function buildStoryTurnSystemPrompt(input: StoryTurnPromptInput): string {
  const level = input.kid.readingLevel as ReadingLevel;
  const interests = Array.from(
    new Set([...input.kid.interests, ...input.brief.interests]),
  );

  const lines: string[] = [
    `You are Pop!'s story engine, writing a live picture book with a parent for their child ${input.kid.firstName}.`,
    describeReadingLevelForPrompt(level),
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
    "Respond with only the JSON object the response schema describes.",
  );

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
