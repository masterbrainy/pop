import { assertEquals } from "jsr:@std/assert@1";
import { checkBriefSafety, collectBriefTexts } from "./brief_safety.ts";
import { kidRealHarmNote, type InputSafetyDeps } from "./input_safety.ts";
import { gentleParentNote } from "./safety.ts";
import type { Kid, StoryBrief } from "./schemas.ts";

const kid: Kid = { firstName: "Maya", readingLevel: "early_reader", interests: [] };
const tileOnlyBrief: StoryBrief = {
  interests: [],
  realMoment: null,
  teach: null,
  language: "en",
  hero: { tile: "dragon" },
  place: { tile: "castle" },
  problem: { tile: "lost" },
  mood: "silly",
  purpose: "fun",
};

interface Recorded {
  moderated: string[];
  realHarm: string[];
  secondOpinion: string[];
}

function recordingDeps(overrides: Partial<InputSafetyDeps> = {}): { deps: InputSafetyDeps; recorded: Recorded } {
  const recorded: Recorded = { moderated: [], realHarm: [], secondOpinion: [] };
  const deps: InputSafetyDeps = {
    moderateText: async (text) => {
      recorded.moderated.push(text);
      return { flagged: false, categories: [] };
    },
    checkRealHarm: async (text) => {
      recorded.realHarm.push(text);
      return { safe: true, reason: "" };
    },
    checkDirectionSafety: async (text) => {
      recorded.secondOpinion.push(text);
      return { safe: true, reason: "" };
    },
    ...overrides,
  };
  return { deps, recorded };
}

Deno.test("collectBriefTexts splits free text into typed and speech", () => {
  const brief: StoryBrief = {
    ...tileOnlyBrief,
    interests: ["owls"],
    realMoment: "starting a new school",
    teach: "sharing",
    hero: { text: "a purple owl", via: "speech" },
    place: { text: "Grandma's garden", via: "typed" },
  };
  const texts = collectBriefTexts(brief, { ...kid, interests: ["trains"] });
  assertEquals(texts.typed, ["owls", "trains", "starting a new school", "sharing", "Grandma's garden"]);
  assertEquals(texts.speech, ["a purple owl"]);
});

Deno.test("checkBriefSafety makes zero safety calls for a tile-only brief", async () => {
  const { deps, recorded } = recordingDeps();
  const verdict = await checkBriefSafety(tileOnlyBrief, kid, deps);
  assertEquals(verdict, { blocked: false, parentNote: null, refusal: null });
  assertEquals(recorded, { moderated: [], realHarm: [], secondOpinion: [] });
});

Deno.test("checkBriefSafety sends typed text as one parent/typed check: moderation only, no real-harm rubric", async () => {
  const { deps, recorded } = recordingDeps();
  const brief: StoryBrief = { ...tileOnlyBrief, interests: ["owls"], teach: "sharing" };
  const verdict = await checkBriefSafety(brief, { ...kid, interests: ["trains"] }, deps);
  assertEquals(verdict.blocked, false);
  assertEquals(recorded.moderated, ["owls\ntrains\nsharing"]);
  assertEquals(recorded.realHarm, []);
});

Deno.test("checkBriefSafety sends spoken answers as one parent/speech check, so they get the real-harm rubric", async () => {
  const { deps, recorded } = recordingDeps();
  const brief: StoryBrief = {
    ...tileOnlyBrief,
    hero: { text: "a purple owl", via: "speech" },
    problem: { text: "the owl is sleepy", via: "speech" },
  };
  const verdict = await checkBriefSafety(brief, kid, deps);
  assertEquals(verdict.blocked, false);
  assertEquals(recorded.moderated, ["a purple owl\nthe owl is sleepy"]);
  assertEquals(recorded.realHarm, ["a purple owl\nthe owl is sleepy"]);
});

Deno.test("checkBriefSafety runs the typed and speech checks together", async () => {
  const { deps, recorded } = recordingDeps();
  const brief: StoryBrief = { ...tileOnlyBrief, realMoment: "a new baby sister", hero: { text: "a purple owl", via: "speech" } };
  await checkBriefSafety(brief, kid, deps);
  assertEquals(recorded.moderated.sort(), ["a new baby sister", "a purple owl"]);
  assertEquals(recorded.realHarm, ["a purple owl"]);
});

Deno.test("checkBriefSafety blocks unsafe typed text when the second opinion agrees", async () => {
  const { deps } = recordingDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkDirectionSafety: async () => ({ safe: false, reason: "unsafe" }),
  });
  const brief: StoryBrief = { ...tileOnlyBrief, hero: { text: "something unsafe", via: "typed" } };
  const verdict = await checkBriefSafety(brief, kid, deps);
  assertEquals(verdict, { blocked: true, parentNote: gentleParentNote(), refusal: "unsafe" });
});

Deno.test("checkBriefSafety reports a spoken real-harm answer as real_harm, ahead of a typed block", async () => {
  const { deps } = recordingDeps({
    moderateText: async () => ({ flagged: true, categories: ["violence"] }),
    checkRealHarm: async () => ({ safe: false, reason: "sounds like real harm" }),
    checkDirectionSafety: async () => ({ safe: false, reason: "unsafe" }),
  });
  const brief: StoryBrief = {
    ...tileOnlyBrief,
    teach: "something unsafe",
    problem: { text: "something that sounds like real harm", via: "speech" },
  };
  const verdict = await checkBriefSafety(brief, kid, deps);
  assertEquals(verdict, { blocked: true, parentNote: kidRealHarmNote("Maya"), refusal: "real_harm" });
});
