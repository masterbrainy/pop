import { assert } from "jsr:@std/assert@1";
import { directionSafetyCheckPrompt, KID_SAFETY_RUBRIC } from "./safety_rubric.ts";

Deno.test("directionSafetyCheckPrompt judges a parent's direction against the full kid-safety rubric (R-44)", () => {
  const prompt = directionSafetyCheckPrompt();
  assert(prompt.includes(KID_SAFETY_RUBRIC));
  assert(prompt.includes("as young as 3"));
});
