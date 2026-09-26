import { assertEquals } from "jsr:@std/assert@1";
import { closeWithTheEnd } from "./ending.ts";
import { withinWordLimit } from "./reading_levels.ts";

Deno.test("closeWithTheEnd adds 'The end.' to the ending page", () => {
  assertEquals(
    closeWithTheEnd("Micah and the owl curl up in a moss nest.", "early_reader"),
    "Micah and the owl curl up in a moss nest. The end.",
  );
});

Deno.test("closeWithTheEnd leaves a page that already ends with 'The end' alone", () => {
  assertEquals(closeWithTheEnd("They sleep together. The end.", "listener"), "They sleep together. The end.");
  assertEquals(closeWithTheEnd("They sleep together. THE END!", "listener"), "They sleep together. THE END!");
});

Deno.test("closeWithTheEnd drops the last sentence when 'The end.' would go over the word limit", () => {
  const full = "one two three four five six seven eight nine ten. eleven twelve thirteen fourteen fifteen.";
  const closed = closeWithTheEnd(full, "listener");
  assertEquals(withinWordLimit(closed, "listener"), true);
  assertEquals(closed.endsWith(" The end."), true);
});
