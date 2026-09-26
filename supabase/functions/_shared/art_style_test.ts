import { assert, assertEquals } from "jsr:@std/assert@1";
import { aspectRatioFor, ART_STYLE, ART_STYLE_PREFIX } from "./art_style.ts";

Deno.test("aspectRatioFor: cover is 2:3, character is 1:1, everything else is 16:9", () => {
  assertEquals(aspectRatioFor("cover"), "2:3");
  assertEquals(aspectRatioFor("character"), "1:1");
  assertEquals(aspectRatioFor("page"), "16:9");
  assertEquals(aspectRatioFor("plate"), "16:9");
  assertEquals(aspectRatioFor("cutout"), "16:9");
});

Deno.test("ART_STYLE forbids text and borders so pages stay style-locked", () => {
  assertEquals(ART_STYLE.includes("no text"), true);
  assertEquals(ART_STYLE.includes("no borders"), true);
});

Deno.test("ART_STYLE starts with ART_STYLE_PREFIX (single source of truth for motion-prompt)", () => {
  assert(ART_STYLE.startsWith(ART_STYLE_PREFIX));
});
