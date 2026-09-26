import { assert, assertEquals } from "jsr:@std/assert@1";
import { SETUP_CARDS, SETUP_TILES, tilePhrase } from "./setup_tiles.ts";
import { READING_LEVELS } from "./reading_levels.ts";
import { isChoiceSymbol } from "./choice_symbols.ts";

Deno.test("every setup tile has an id, card, phrase, symbol and at least one reading level", () => {
  for (const tile of SETUP_TILES) {
    assert(tile.id.trim().length > 0, `tile with empty id: ${JSON.stringify(tile)}`);
    assert((SETUP_CARDS as readonly string[]).includes(tile.card), `${tile.id}: unknown card ${tile.card}`);
    assert(tile.phrase.trim().length > 0, `${tile.id}: empty phrase`);
    assert(tile.symbol.trim().length > 0, `${tile.id}: empty symbol`);
    assert(tile.levels.length > 0, `${tile.id}: no levels`);
    for (const level of tile.levels) {
      assert((READING_LEVELS as readonly string[]).includes(level), `${tile.id}: unknown level ${level}`);
    }
  }
});

Deno.test("setup tile ids are unique and the catalog has about 40 tiles", () => {
  const ids = SETUP_TILES.map((tile) => tile.id);
  assertEquals(new Set(ids).size, ids.length);
  assert(ids.length >= 35 && ids.length <= 45, `expected ~40 tiles, got ${ids.length}`);
});

Deno.test("every card has tiles for every reading level", () => {
  for (const card of SETUP_CARDS) {
    for (const level of READING_LEVELS) {
      assert(
        SETUP_TILES.some((tile) => tile.card === card && tile.levels.includes(level)),
        `no ${card} tile for ${level}`,
      );
    }
  }
});

Deno.test("every setup tile's symbol is on the choice-symbol allow-list", () => {
  for (const tile of SETUP_TILES) assert(isChoiceSymbol(tile.symbol), `${tile.id}: ${tile.symbol}`);
});

Deno.test("tilePhrase returns the tile's phrase with {kid} replaced by the kid's first name", () => {
  assertEquals(tilePhrase("dragon", "hero", "Maya"), "a small, friendly dragon");
  assertEquals(tilePhrase("kid", "hero", "Maya"), "Maya, the child this book is for");
  assertEquals(tilePhrase("castle", "place", "Maya"), "in a friendly castle");
});

Deno.test("tilePhrase ignores an unknown id or a tile used on the wrong card", () => {
  assertEquals(tilePhrase("hoverboard", "hero", "Maya"), null);
  assertEquals(tilePhrase("dragon", "place", "Maya"), null);
  assertEquals(tilePhrase("lost", "hero", "Maya"), null);
});
