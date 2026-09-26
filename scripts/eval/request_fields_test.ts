import { assertEquals } from "jsr:@std/assert@1";
import { kidAndBriefFor } from "./request_fields.ts";
import { requestSchema } from "../../supabase/functions/story-turn/schema.ts";
import type { EvalCase } from "./types.ts";

Deno.test("kidAndBriefFor sends the brief's interests for both kid and brief when no profile interests are set", () => {
  const fields = kidAndBriefFor({ kidFirstName: "Maya", readingLevel: "listener", interests: ["owls"] });
  assertEquals(fields.kid, { firstName: "Maya", readingLevel: "listener", interests: ["owls"] });
  assertEquals(fields.brief, { interests: ["owls"], realMoment: null, teach: null, language: "en" });
});

Deno.test("kidAndBriefFor sends profileInterests as kid.interests and setup answers on the brief", () => {
  const fields = kidAndBriefFor({
    kidFirstName: "Maya",
    readingLevel: "early_reader",
    interests: [],
    profileInterests: ["foxes", "stars"],
    setup: { hero: { tile: "dragon" }, place: { tile: "castle" }, mood: "silly" },
  });
  assertEquals(fields.kid.interests, ["foxes", "stars"]);
  assertEquals(fields.brief, {
    interests: [],
    realMoment: null,
    teach: null,
    language: "en",
    hero: { tile: "dragon" },
    place: { tile: "castle" },
    mood: "silly",
  });
});

Deno.test("every case's kid and brief pass the deployed request schema", async () => {
  const { cases } = JSON.parse(await Deno.readTextFile(new URL("cases.json", import.meta.url))) as { cases: EvalCase[] };
  for (const evalCase of cases) {
    const body = {
      mode: "path",
      bookId: "123e4567-e89b-12d3-a456-426614174000",
      ...kidAndBriefFor(evalCase.brief),
      settings: { avoidTopics: [] },
      bible: { title: null, setting: "", characters: [], directions: [], path: [] },
      pages: [],
      index: 0,
    };
    assertEquals(requestSchema.safeParse(body).success, true, evalCase.id);
  }
});

Deno.test("the IMP-24 cases are present and shaped as intended", async () => {
  const { cases } = JSON.parse(await Deno.readTextFile(new URL("cases.json", import.meta.url))) as { cases: EvalCase[] };
  const bookBeatsProfile = cases.find((c) => c.id === "book-beats-profile");
  assertEquals(bookBeatsProfile?.brief.profileInterests, ["foxes", "stars"]);
  assertEquals(bookBeatsProfile?.expect.mustNotContain, ["fox"]);
  const unsafeBrief = cases.find((c) => c.id === "unsafe-brief-free-text");
  assertEquals(unsafeBrief?.expect.mustBlockOrSoften, true);
});
