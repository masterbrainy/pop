import { assertEquals } from "jsr:@std/assert@1";
import { brandedCharactersIn } from "./brand_check.ts";

Deno.test("brandedCharactersIn finds well-known branded characters, ignoring case and spacing", () => {
  assertEquals(brandedCharactersIn("Mickey  Mouse and JJ from cocomelon wave hello."), ["mickey mouse", "cocomelon"]);
  assertEquals(brandedCharactersIn("A sponge like SpongeBob SquarePants dances."), ["spongebob"]);
  assertEquals(brandedCharactersIn("Spider-Man swings by."), ["spider-man"]);
});

Deno.test("brandedCharactersIn leaves invented characters and ordinary words alone", () => {
  assertEquals(brandedCharactersIn("A little mouse named Mick found a peppery pie and a paw print."), []);
  assertEquals(brandedCharactersIn("Sara and Star Fox watch the stars."), []);
});

Deno.test("brandedCharactersIn matches whole words only", () => {
  assertEquals(brandedCharactersIn("The elsewhere garden bloomed."), []);
  assertEquals(brandedCharactersIn("Elsa waves from the ice castle."), ["elsa"]);
});

Deno.test("brandedCharactersIn never flags the kid's own first name", () => {
  assertEquals(brandedCharactersIn("Elsa builds a snow fort with Olaf.", "Elsa"), ["olaf"]);
  assertEquals(brandedCharactersIn("Moana paddles to the island.", "moana"), []);
});

Deno.test("brandedCharactersIn leaves everyday words like goofy and hulking alone", () => {
  assertEquals(brandedCharactersIn("The goofy goat did a hulking hop."), []);
});
