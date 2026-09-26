import { assertEquals } from "jsr:@std/assert@1";
import { buildArtPrompt, referencePathsFor, STANDARD_DIMENSIONS } from "./art_request.ts";
import type { Character } from "./schemas.ts";

const rex: Character = { id: "rex", name: "Rex", description: "a friendly green dinosaur", referencePath: "u/b/character-rex-v1.png" };
const maya: Character = { id: "maya", name: "Maya", description: "a curious kid", referencePath: null };

Deno.test("referencePathsFor: page/cover include every character with a saved reference", () => {
  assertEquals(referencePathsFor("page", [rex, maya]), ["u/b/character-rex-v1.png"]);
  assertEquals(referencePathsFor("cover", [rex, maya]), ["u/b/character-rex-v1.png"]);
});

Deno.test("referencePathsFor: cutout/character include only the matching characterId", () => {
  assertEquals(referencePathsFor("cutout", [rex, maya], "rex"), ["u/b/character-rex-v1.png"]);
  assertEquals(referencePathsFor("character", [rex, maya], "maya"), []); // maya has no referencePath yet
  assertEquals(referencePathsFor("cutout", [rex, maya], "nobody"), []);
});

Deno.test("referencePathsFor: plate never includes any character", () => {
  assertEquals(referencePathsFor("plate", [rex, maya]), []);
});

Deno.test("buildArtPrompt always starts with the locked art style", () => {
  const prompt = buildArtPrompt("page", "A sunny meadow", []);
  assertEquals(prompt.startsWith(prompt.split("\n\n")[0]), true);
  assertEquals(prompt.includes("watercolor"), true);
});

Deno.test("buildArtPrompt adds the flat magenta backdrop instruction only for cutout", () => {
  assertEquals(buildArtPrompt("cutout", "Rex waving", [rex], "rex").includes("solid magenta background"), true);
  assertEquals(buildArtPrompt("page", "Rex waving", [rex]).includes("solid magenta background"), false);
});

Deno.test("buildArtPrompt adds the no-characters instruction only for plate", () => {
  assertEquals(buildArtPrompt("plate", "An empty meadow", []).includes("no characters present"), true);
  assertEquals(buildArtPrompt("page", "A meadow", []).includes("no characters present"), false);
});

Deno.test("buildArtPrompt names the single character for cutout/character kinds", () => {
  const prompt = buildArtPrompt("cutout", "waving hello", [rex, maya], "rex");
  assertEquals(prompt.includes("Rex"), true);
  assertEquals(prompt.includes("a friendly green dinosaur"), true);
  assertEquals(prompt.includes("Maya"), false);
});

Deno.test("buildArtPrompt lists every character for page/cover kinds", () => {
  const prompt = buildArtPrompt("page", "playing together", [rex, maya]);
  assertEquals(prompt.includes("Rex"), true);
  assertEquals(prompt.includes("Maya"), true);
});

Deno.test("buildArtPrompt always ends with the caller's own prompt", () => {
  const prompt = buildArtPrompt("cover", "the whole gang on an adventure", []);
  assertEquals(prompt.endsWith("the whole gang on an adventure"), true);
});

Deno.test("STANDARD_DIMENSIONS matches CONTRACTS.md's example for 16:9", () => {
  assertEquals(STANDARD_DIMENSIONS["16:9"], { width: 1344, height: 768 });
});
