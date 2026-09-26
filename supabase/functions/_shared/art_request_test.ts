import { assertEquals } from "jsr:@std/assert@1";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { buildArtPrompt, charactersIn, drawingInlineImage, referencePathsFor, STANDARD_DIMENSIONS } from "./art_request.ts";
import type { Character } from "./schemas.ts";

const rex: Character = { id: "rex", name: "Rex", description: "a friendly green dinosaur", referencePath: "u/b/character-rex-v1.png" };
const maya: Character = { id: "maya", name: "Maya", description: "a curious kid", referencePath: null };

Deno.test("referencePathsFor: cover includes every character with a saved reference", () => {
  assertEquals(referencePathsFor("cover", [rex, maya]), ["u/b/character-rex-v1.png"]);
});

Deno.test("referencePathsFor: page includes only the characters its prompt names that have a saved reference", () => {
  assertEquals(referencePathsFor("page", [rex, maya], null, "Rex and Maya fly a kite"), ["u/b/character-rex-v1.png"]);
  assertEquals(referencePathsFor("page", [rex, maya], null, "Maya flies a kite"), []);
  assertEquals(referencePathsFor("page", [rex, maya], null, "An empty meadow"), []);
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
  const page = buildArtPrompt("page", "Rex and Maya playing together", [rex, maya]);
  assertEquals(page.includes("a friendly green dinosaur"), true);
  assertEquals(page.includes("a curious kid"), true);
  const cover = buildArtPrompt("cover", "playing together", [rex, maya]);
  assertEquals(cover.includes("Rex"), true);
  assertEquals(cover.includes("Maya"), true);
});

// A page picture draws only the characters its own prompt names: sending every
// bible character (and every reference image) painted absent characters in.
const bella: Character = { id: "bella", name: "Bella the bunny", description: "a small white bunny", referencePath: "u/b/character-bella-v1.png" };
const rusty: Character = { id: "rusty", name: "Rusty the fox", description: "a red fox", referencePath: "u/b/character-rusty-v1.png" };

Deno.test("buildArtPrompt and referencePathsFor leave out a character the page prompt doesn't name", () => {
  const pagePrompt = "Bella hops through the snowy garden";
  const prompt = buildArtPrompt("page", pagePrompt, [bella, rusty]);
  assertEquals(prompt.includes("Rusty"), false);
  assertEquals(prompt.includes("a red fox"), false);
  assertEquals(prompt.includes("a small white bunny"), true);
  assertEquals(referencePathsFor("page", [bella, rusty], null, pagePrompt), ["u/b/character-bella-v1.png"]);
});

Deno.test("buildArtPrompt lists no characters when the page prompt names none of them", () => {
  const prompt = buildArtPrompt("page", "A quiet snowy garden at dawn", [bella, rusty]);
  assertEquals(prompt.includes("Characters appearing in this picture"), false);
});

Deno.test("buildArtPrompt and referencePathsFor keep every character for a cover", () => {
  const prompt = buildArtPrompt("cover", "Bella hops through the snowy garden", [bella, rusty]);
  assertEquals(prompt.includes("Rusty the fox"), true);
  assertEquals(prompt.includes("Bella the bunny"), true);
  assertEquals(referencePathsFor("cover", [bella, rusty], null, "Bella hops"), [
    "u/b/character-bella-v1.png",
    "u/b/character-rusty-v1.png",
  ]);
});

Deno.test("charactersIn matches a whole name phrase or the id, ignoring case", () => {
  assertEquals(charactersIn("bella the bunny naps", [bella, rusty]), [bella]);
  assertEquals(charactersIn("RUSTY waves hello", [bella, rusty]), [rusty]);
  assertEquals(charactersIn("Rusty the Fox and Bella share a carrot", [bella, rusty]), [bella, rusty]);
});

Deno.test("charactersIn matches whole words only", () => {
  assertEquals(charactersIn("A trip to Rustyville", [bella, rusty]), []);
  assertEquals(charactersIn("Isabella reads a book", [bella, rusty]), []);
  assertEquals(charactersIn("Rusty's tail swishes.", [bella, rusty]), [rusty]);
});

Deno.test("charactersIn treats regex characters in a name literally", () => {
  const dot: Character = { id: "mr-dot", name: "Mr. Dot (the ladybug)", description: "a ladybug", referencePath: null };
  assertEquals(charactersIn("Mr. Dot (the ladybug) lands on a leaf", [dot]), [dot]);
  assertEquals(charactersIn("Mrs Dotty lands on a leaf", [dot]), []);
});

Deno.test("charactersIn matches a name with letters outside English", () => {
  const zoe: Character = { id: "zoe", name: "Zoë", description: "a girl", referencePath: null };
  assertEquals(charactersIn("Zoë paints a boat", [zoe]), [zoe]);
  assertEquals(charactersIn("Zoëtrope spins", [zoe]), []);
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
