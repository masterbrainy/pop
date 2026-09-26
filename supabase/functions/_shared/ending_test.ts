import { assertEquals } from "jsr:@std/assert@1";
import { closeWithTheEnd } from "./ending.ts";

Deno.test("closeWithTheEnd adds 'The end.' to the ending page", () => {
  assertEquals(
    closeWithTheEnd("Micah and the owl curl up in a moss nest."),
    "Micah and the owl curl up in a moss nest. The end.",
  );
});

Deno.test("closeWithTheEnd leaves a page that already ends with 'The end' alone", () => {
  assertEquals(closeWithTheEnd("They sleep together. The end."), "They sleep together. The end.");
  assertEquals(closeWithTheEnd("They sleep together. THE END!"), "They sleep together. THE END!");
});

Deno.test("closeWithTheEnd never cuts the story's words; the ending page may run two words over (R-45)", () => {
  const full = "one two three four five six seven eight nine ten. eleven twelve thirteen fourteen fifteen.";
  assertEquals(closeWithTheEnd(full), `${full} The end.`);
  assertEquals(closeWithTheEnd("The big bear hugs the little fox so they never feel alone or scared again"),
    "The big bear hugs the little fox so they never feel alone or scared again. The end.");
});
