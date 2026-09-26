// The kid and brief a case sends on every story-turn call (pure, so the
// mapping is unit-testable without the network; used by run.ts).
import type { EvalBrief } from "./types.ts";

export interface KidAndBrief {
  kid: { firstName: string; readingLevel: string; interests: string[] };
  brief: Record<string, unknown>;
}

/**
 * `kid.interests` is the profile's (profileInterests), falling back to the
 * brief's own interests for cases written before IMP-24; the setup answers
 * (hero/place/problem/mood/purpose) ride on the brief only when set.
 */
export function kidAndBriefFor(brief: EvalBrief): KidAndBrief {
  return {
    kid: {
      firstName: brief.kidFirstName,
      readingLevel: brief.readingLevel,
      interests: brief.profileInterests ?? brief.interests,
    },
    brief: {
      interests: brief.interests,
      realMoment: brief.realMoment ?? null,
      teach: brief.teach ?? null,
      language: "en",
      ...(brief.setup ?? {}),
    },
  };
}
