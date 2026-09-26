import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { ART_STYLE_PREFIX } from "./art_style.ts";
import { buildMotionPromptInstruction, ensureStyleLockedScene, motionOutputSchema } from "./motion_prompt.ts";

Deno.test("buildMotionPromptInstruction includes the page text and forbids new elements", () => {
  const instruction = buildMotionPromptInstruction("Rex waved at the sun.");
  assert(instruction.includes("Rex waved at the sun."));
  assert(instruction.includes("Nothing new may enter"));
});

Deno.test("buildMotionPromptInstruction asks for exactly one motion clause", () => {
  const instruction = buildMotionPromptInstruction("A quiet meadow.");
  assert(instruction.includes("ONE gentle motion clause"));
});

Deno.test("buildMotionPromptInstruction tells the model scene must start with the locked art style", () => {
  const instruction = buildMotionPromptInstruction("A quiet meadow.");
  assert(instruction.includes(ART_STYLE_PREFIX));
});

Deno.test("motionOutputSchema accepts {scene, motion} and rejects missing fields", () => {
  assert(motionOutputSchema.safeParse({ scene: "a meadow", motion: "grass sways" }).success);
  assertFalse(motionOutputSchema.safeParse({ scene: "a meadow" }).success);
});

Deno.test("ensureStyleLockedScene leaves a scene that already starts with the style alone", () => {
  const scene = `${ART_STYLE_PREFIX} of a dinosaur in a meadow.`;
  assertEquals(ensureStyleLockedScene(scene), scene);
});

Deno.test("ensureStyleLockedScene prepends the style to a drifted (e.g. photoreal) scene", () => {
  const scene = ensureStyleLockedScene("A photorealistic dinosaur stands in a sunlit meadow.");
  assert(scene.startsWith(ART_STYLE_PREFIX));
  assert(scene.includes("a photorealistic dinosaur stands in a sunlit meadow."));
});

Deno.test("ensureStyleLockedScene is case-insensitive when checking for an existing prefix", () => {
  const scene = "SOFT WATERCOLOR AND COLORED PENCIL CHILDREN'S PICTURE-BOOK ILLUSTRATION of a garden.";
  assertEquals(ensureStyleLockedScene(scene), scene);
});

Deno.test("ensureStyleLockedScene handles an empty scene without throwing", () => {
  assertEquals(ensureStyleLockedScene(""), ART_STYLE_PREFIX);
});
