// IMP-24 guided setup → prompt lines, shared by the path and page prompts
// (story_prompt.ts). Pure functions of the brief and kid.
import { type SetupCard, tilePhrase } from "./setup_tiles.ts";
import type { BriefAnswer, Kid, Mood, StoryBrief } from "./schemas.ts";

interface CardWording {
  /** Before a tile's phrase, e.g. "The story takes place" + " in a leafy forest." */
  tileLead: string;
  /** Before the family's own words, quoted. */
  textLead: string;
}

const CARD_WORDING: Record<SetupCard, CardWording> = {
  hero: { tileLead: "The hero of this story is", textLead: "The hero of this story, in the family's own words:" },
  place: { tileLead: "The story takes place", textLead: "Where the story happens, in the family's own words:" },
  problem: { tileLead: "What goes wrong:", textLead: "What goes wrong, in the family's own words:" },
};

const MOOD_LINES: Record<Mood, string> = {
  silly: "Make the tone silly and playful, with gentle giggles and funny surprises.",
  cosy: "Make the tone cosy, warm and calm.",
  brave: "Make the tone brave and adventurous — a small, safe challenge the hero bravely meets, never scary.",
};

const BEDTIME_LINE = "This is a bedtime story: keep it calm, and end it quiet, snuggly and sleepy.";

/** One line of the family's own words: whitespace collapsed and double quotes softened so it stays one quoted phrase. */
function quoted(text: string): string {
  return `"${text.replace(/\s+/g, " ").replaceAll('"', "'").trim()}"`;
}

function answerLine(answer: BriefAnswer | null | undefined, card: SetupCard, kidFirstName: string): string[] {
  if (!answer) return [];
  const wording = CARD_WORDING[card];
  if ("text" in answer) return [`${wording.textLead} ${quoted(answer.text)}.`];
  const phrase = tilePhrase(answer.tile, card, kidFirstName);
  return phrase === null ? [] : [`${wording.tileLead} ${phrase}.`];
}

/** Prompt lines for the setup cards, mood, purpose, real moment and "teach" (only those that are set). */
export function describeSetup(brief: StoryBrief, kid: Kid): string[] {
  const lines = [
    ...answerLine(brief.hero, "hero", kid.firstName),
    ...answerLine(brief.place, "place", kid.firstName),
    ...answerLine(brief.problem, "problem", kid.firstName),
  ];
  if (brief.mood) lines.push(MOOD_LINES[brief.mood]);
  if (brief.purpose === "bedtime") lines.push(BEDTIME_LINE);
  if (brief.realMoment) {
    lines.push(
      `This story gently helps with a real moment: ${brief.realMoment}. Keep the tone calm and hopeful, and end reassuringly.`,
    );
  }
  if (brief.teach) {
    lines.push(`If it fits naturally, let the story help teach: ${brief.teach}.`);
  }
  return lines;
}

function hasCardAnswers(brief: StoryBrief): boolean {
  return [brief.hero, brief.place, brief.problem].some((answer) => answer != null);
}

/**
 * "Book interests win" (contract): the "loves" line uses only the brief's
 * interests once the brief has card answers or interests of its own;
 * otherwise the profile's. (The profile's still feed the brand guard.)
 */
export function lovedInterests(brief: StoryBrief, kid: Kid): string[] {
  const source = hasCardAnswers(brief) || brief.interests.length > 0 ? brief.interests : kid.interests;
  return Array.from(new Set(source));
}

/** Every free-text answer (hero/place/problem typed or spoken), for the brand guard. */
export function setupAnswerTexts(brief: StoryBrief): string[] {
  return [brief.hero, brief.place, brief.problem].flatMap((answer) => (answer && "text" in answer ? [answer.text] : []));
}
