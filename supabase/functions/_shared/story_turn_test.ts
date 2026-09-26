import { assertEquals } from "jsr:@std/assert@1";
import { mergeBibleCharacters, stripRepeatedEarlierText, trimToLimit } from "./story_turn.ts";

Deno.test("mergeBibleCharacters returns null referencePath for a brand-new bible", () => {
  const result = mergeBibleCharacters([], [{ id: "c1", name: "Rex", description: "a dinosaur" }]);
  assertEquals(result, [{ id: "c1", name: "Rex", description: "a dinosaur", referencePath: null }]);
});

Deno.test("mergeBibleCharacters preserves an existing character's referencePath by id", () => {
  const existing = [{ id: "c1", name: "Rex", description: "a dinosaur", referencePath: "u/b/character-c1-v1.png" }];
  const result = mergeBibleCharacters(existing, [
    { id: "c1", name: "Rex", description: "a friendly green dinosaur" },
    { id: "c2", name: "Maya", description: "a curious kid" },
  ]);
  assertEquals(result, [
    { id: "c1", name: "Rex", description: "a friendly green dinosaur", referencePath: "u/b/character-c1-v1.png" },
    { id: "c2", name: "Maya", description: "a curious kid", referencePath: null },
  ]);
});

Deno.test("trimToLimit leaves a page within the limit alone (just trimmed)", () => {
  assertEquals(trimToLimit("  Maya flies.  ", "listener"), "Maya flies.");
});

Deno.test("trimToLimit trims an overlong page to whole sentences within the limit", () => {
  const long = "Maya flies up. The kite flies too. They dance and spin and twirl around the sunny sky all day long.";
  assertEquals(trimToLimit(long, "listener"), "Maya flies up. The kite flies too.");
});

Deno.test("trimToLimit cuts a single overlong sentence at the word limit", () => {
  const words = Array.from({ length: 20 }, (_, i) => `w${i}`).join(" ");
  const trimmed = trimToLimit(`${words}.`, "listener");
  assertEquals(trimmed.split(" ").length, 15);
  assertEquals(trimmed.endsWith("."), true);
});

Deno.test("stripRepeatedEarlierText strips a new page that restarts with the page before it", () => {
  const earlier = ["Maya the little blue dragon finds a shiny red kite in the meadow."];
  const repeated = "Maya the little blue dragon finds a shiny red kite in the meadow. She smiles and lifts it high.";
  assertEquals(stripRepeatedEarlierText(repeated, earlier), "She smiles and lifts it high.");
});

Deno.test("stripRepeatedEarlierText strips several earlier pages repeated in order, ignoring case and spacing", () => {
  const earlier = ["One day Maya flew.", "Then she  landed!"];
  const repeated = "one day maya flew. Then she landed! And she slept.";
  assertEquals(stripRepeatedEarlierText(repeated, earlier), "And she slept.");
});

Deno.test("stripRepeatedEarlierText leaves a page alone when it doesn't repeat, or would be left empty", () => {
  const earlier = ["Maya flew."];
  assertEquals(stripRepeatedEarlierText("Maya landed softly.", earlier), "Maya landed softly.");
  assertEquals(stripRepeatedEarlierText("Maya flew.", earlier), "Maya flew.");
});
