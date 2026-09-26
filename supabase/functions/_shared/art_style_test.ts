import { assertEquals } from "jsr:@std/assert@1";
import { ART_STYLE_PREFIX, namesAnotherStyle, withoutStyleDrift } from "./art_style.ts";
import { buildArtPrompt } from "./art_request.ts";

Deno.test("namesAnotherStyle spots medium, camera and rendering words", () => {
  assertEquals(namesAnotherStyle("A photorealistic fox in a meadow"), true);
  assertEquals(namesAnotherStyle("Rex the dragon, 3D render, cinematic lighting"), true);
  assertEquals(namesAnotherStyle("Bella naps under a big oak tree"), false);
});

Deno.test("withoutStyleDrift cuts those words and tidies the sentence", () => {
  assertEquals(withoutStyleDrift("A photorealistic, cinematic fox in a sunny meadow, 8k"), "A fox in a sunny meadow");
  assertEquals(withoutStyleDrift("Bella naps under a big oak tree"), "Bella naps under a big oak tree");
});

Deno.test("buildArtPrompt opens and closes with the locked style around the cleaned scene", () => {
  const prompt = buildArtPrompt("page", "A 3D render of a fox by a pond", []);
  const lines = prompt.split("\n\n");
  assertEquals(lines[0].startsWith(ART_STYLE_PREFIX), true);
  assertEquals(lines.includes("A of a fox by a pond") || lines.includes("A fox by a pond") || lines.some((l) => l.includes("fox by a pond") && !l.includes("3D")), true);
  assertEquals(lines[lines.length - 1].includes("no photorealism"), true);
});
