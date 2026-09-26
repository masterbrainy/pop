// Brief-side kid-safety gate (IMP-24, R-37): the brief's free text — its own
// and the profile's interests, the real moment, "teach", and any typed or
// spoken hero/place/problem answer — reaches every path/page prompt, so it
// is checked before any model call, the same way a direction is
// (input_safety.ts). Typed words are the parent's; spoken words may be the
// kid's, so they get the real-harm check too (R-44). A tile-only brief has no
// free text and costs no network call at all.
import {
  checkInputSafety,
  firstBlockingVerdict,
  type InputSafetyDeps,
  type InputSafetyVerdict,
  SAFE_INPUT,
} from "./input_safety.ts";
import type { BriefAnswer, Kid, StoryBrief } from "./schemas.ts";

export interface BriefTexts {
  typed: string[];
  speech: string[];
}

function answerText(answer: BriefAnswer | null | undefined, via: "typed" | "speech"): string[] {
  if (!answer || !("text" in answer) || answer.via !== via) return [];
  return [answer.text];
}

/** Pure: every piece of free text in the brief and profile, split by how it arrived. */
export function collectBriefTexts(brief: StoryBrief, kid: Kid): BriefTexts {
  const answers = [brief.hero, brief.place, brief.problem];
  const nonEmpty = (texts: string[]) => texts.map((t) => t.trim()).filter((t) => t.length > 0);
  return {
    typed: nonEmpty([
      ...brief.interests,
      ...kid.interests,
      brief.realMoment ?? "",
      brief.teach ?? "",
      ...answers.flatMap((a) => answerText(a, "typed")),
    ]),
    speech: nonEmpty(answers.flatMap((a) => answerText(a, "speech"))),
  };
}

/**
 * Checks the brief's free text as at most two parent inputs, run together:
 * all typed text joined into one "typed" check, all spoken answers into one
 * "speech" check (which adds the real-harm rubric). A spoken real-harm block
 * wins over a typed one, since it carries the calmer, more useful note.
 */
export async function checkBriefSafety(brief: StoryBrief, kid: Kid, deps: InputSafetyDeps): Promise<InputSafetyVerdict> {
  const { typed, speech } = collectBriefTexts(brief, kid);
  const check = (texts: string[], kind: "typed" | "speech") =>
    texts.length === 0 ? Promise.resolve(SAFE_INPUT) : checkInputSafety(texts.join("\n"), "parent", kid.firstName, deps, kind);
  return firstBlockingVerdict(await Promise.all([check(speech, "speech"), check(typed, "typed")]));
}
