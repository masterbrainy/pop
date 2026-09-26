import { assertEquals } from "jsr:@std/assert@1";
import { parseModerationResponse } from "./openai_moderation.ts";

Deno.test("parseModerationResponse: safe content is not flagged with no categories", () => {
  const verdict = parseModerationResponse({
    results: [{ flagged: false, categories: { violence: false, sexual: false } }],
  });
  assertEquals(verdict, { flagged: false, categories: [] });
});

Deno.test("parseModerationResponse: flagged content lists only the true categories", () => {
  const verdict = parseModerationResponse({
    results: [{
      flagged: true,
      categories: { violence: true, sexual: false, harassment: true },
    }],
  });
  assertEquals(verdict.flagged, true);
  assertEquals(verdict.categories.sort(), ["harassment", "violence"]);
});

Deno.test("parseModerationResponse: an empty results array is treated as safe", () => {
  assertEquals(parseModerationResponse({ results: [] }), { flagged: false, categories: [] });
});

Deno.test("parseModerationResponse: a missing results field is treated as safe", () => {
  assertEquals(parseModerationResponse({}), { flagged: false, categories: [] });
});
