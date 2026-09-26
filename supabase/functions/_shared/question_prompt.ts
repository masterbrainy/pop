// IMP-25 → the prompt lines asking the story engine for this page's
// `question` object, fitted to the question plan (question_plan.ts). Pure.
import type { QuestionPlan } from "./question_plan.ts";

export interface QuestionPromptInput {
  kidFirstName: string;
  index: number;
  plan: QuestionPlan;
  /**
   * What followsPath must match: page mode passes the already-planned next
   * beat (bible.path[index + 1]); path mode passes null, meaning the next
   * beat of the path the model is returning in this same answer.
   */
  nextPlannedBeat: string | null;
  /** Path mode: the model decides the ending, so the plan can't know yet. */
  endingUnknown: boolean;
}

const CHOICE_FIELDS =
  'Each choice has "label" (a short tile label, at most 4 words), "symbol" (the allowed symbol that best pictures it), "direction" (one sentence, under 120 characters, telling the story what happens next if it is picked) and "followsPath".';

function talkOnlyLine(kid: string): string {
  return `Also write "question" for this page, which the parent says aloud to ${kid}: "ask" is one short, warm talk prompt about this page's words or picture (for example "Can you roar like the dragon?"), with "kind": "talkOnly" and "choices": [].`;
}

function askFor(input: QuestionPromptInput): string {
  const kid = input.kidFirstName;
  if (input.plan.kind === "open") {
    return `"ask" is one open question inviting ${kid} to imagine what happens NEXT (for example "What do you think the dragon should do now?"), with "kind": "open"`;
  }
  const either = input.plan.choiceCount === 2 ? ", asked as an either/or between the two choices" : "";
  return `"ask" is one short, warm question about what could happen NEXT in the story${either}, with "kind": "choice"`;
}

function choicesLine(input: QuestionPromptInput): string {
  const nextBeat = input.nextPlannedBeat === null
    ? `the next beat in the path you return (page ${input.index + 1})`
    : `the next planned beat: "${input.nextPlannedBeat}"`;
  const count = input.plan.choiceCount;
  const role = input.plan.kind === "open" ? "ideas to help if the child gets stuck" : "different things that could happen next";
  return [
    `"choices" holds exactly ${count} choices, ${role}.`,
    CHOICE_FIELDS,
    `Set "followsPath": true on exactly one choice — the one that matches ${nextBeat} — and false on the others.`,
  ].join(" ");
}

/** The question instructions for one page (both modes). */
export function questionInstruction(input: QuestionPromptInput): string[] {
  const kid = input.kidFirstName;
  const rules = `The question and choices are never about ${kid}'s own address, school or family details. A question about ${kid}'s own life (for example "Have you ever lost something?") is only ever "kind": "talkOnly" with "choices": [].`;
  if (input.plan.kind === "talkOnly") return [talkOnlyLine(kid), rules];

  const lines = [
    `Also write "question" for this page, which the parent reads aloud to ${kid}: ${askFor(input)}.`,
    choicesLine(input),
    rules,
  ];
  if (input.endingUnknown) {
    lines.push(`If page ${input.index} is the last beat of the path, make it "kind": "talkOnly" with "choices": [] instead.`);
  }
  return lines;
}
