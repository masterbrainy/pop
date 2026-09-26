import { assertEquals } from "jsr:@std/assert@1";
import { isOpeningIdea } from "./opening_idea.ts";

Deno.test("isOpeningIdea is true only for page 0 with nothing shown and some text", () => {
  assertEquals(isOpeningIdea(0, 0, "a dragon who is scared of the dark"), true);
  assertEquals(isOpeningIdea(0, 1, "a dragon who is scared of the dark"), false);
  assertEquals(isOpeningIdea(1, 0, "a dragon who is scared of the dark"), false);
  assertEquals(isOpeningIdea(0, 0, "   "), false);
  assertEquals(isOpeningIdea(0, 0, null), false);
});
