import { assert, assertFalse } from "jsr:@std/assert@1";
import { buildMotionPromptInstruction, motionOutputSchema } from "./motion_prompt.ts";

Deno.test("buildMotionPromptInstruction includes the page text and forbids new elements", () => {
  const instruction = buildMotionPromptInstruction("Rex waved at the sun.");
  assert(instruction.includes("Rex waved at the sun."));
  assert(instruction.includes("Nothing new may enter"));
});

Deno.test("buildMotionPromptInstruction asks for exactly one motion clause", () => {
  const instruction = buildMotionPromptInstruction("A quiet meadow.");
  assert(instruction.includes("ONE gentle motion clause"));
});

Deno.test("motionOutputSchema accepts {scene, motion} and rejects missing fields", () => {
  assert(motionOutputSchema.safeParse({ scene: "a meadow", motion: "grass sways" }).success);
  assertFalse(motionOutputSchema.safeParse({ scene: "a meadow" }).success);
});
