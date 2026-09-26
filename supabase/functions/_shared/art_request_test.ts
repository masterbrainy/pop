import { assertEquals } from "jsr:@std/assert@1";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { buildArtPrompt, drawingInlineImage, referencePathsFor, STANDARD_DIMENSIONS } from "./art_request.ts";
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

Deno.test("referencePathsFor: drawing never includes any existing character reference", () => {
  assertEquals(referencePathsFor("drawing", [rex, maya], "rex"), []);
});

Deno.test("buildArtPrompt redraws a drawing onto the same magenta backdrop as cutout", () => {
  const prompt = buildArtPrompt("drawing", "a purple cat with wings", []);
  assertEquals(prompt.includes("child's own drawing"), true);
  assertEquals(prompt.includes("solid magenta background"), true);
  assertEquals(prompt.includes("shapes, colours and distinguishing features recognisable"), true);
});

Deno.test("buildArtPrompt ends a drawing prompt with the kid's own description", () => {
  const prompt = buildArtPrompt("drawing", "a purple cat with wings", []);
  assertEquals(prompt.endsWith("a purple cat with wings"), true);
});

Deno.test("drawingInlineImage returns undefined for every kind except drawing", () => {
  const png = encodeBase64(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]));
  assertEquals(drawingInlineImage("cutout", png), undefined);
  assertEquals(drawingInlineImage("page", png), undefined);
});

Deno.test("drawingInlineImage returns undefined when no drawing was sent", () => {
  assertEquals(drawingInlineImage("drawing", undefined), undefined);
  assertEquals(drawingInlineImage("drawing", null), undefined);
});

Deno.test("drawingInlineImage sniffs a PNG drawing's mime type and keeps its base64 data intact", () => {
  const png = encodeBase64(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]));
  const image = drawingInlineImage("drawing", png);
  assertEquals(image, { mimeType: "image/png", data: png });
});

Deno.test("drawingInlineImage sniffs a JPEG drawing's mime type", () => {
  const jpeg = encodeBase64(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]));
  const image = drawingInlineImage("drawing", jpeg);
  assertEquals(image, { mimeType: "image/jpeg", data: jpeg });
});
