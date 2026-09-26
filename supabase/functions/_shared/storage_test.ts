import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { artObjectPath } from "./storage.ts";
import { PopError } from "./errors.ts";

const base = { userId: "user-1", bookId: "book-1", version: 2 };

Deno.test("artObjectPath builds a page path with the page index and version", () => {
  assertEquals(
    artObjectPath({ ...base, kind: "page", pageIndex: 3 }),
    "user-1/book-1/page-3-v2.png",
  );
});

Deno.test("artObjectPath builds a cover path with no page index", () => {
  assertEquals(artObjectPath({ ...base, kind: "cover" }), "user-1/book-1/cover-v2.png");
});

Deno.test("artObjectPath builds a character path from characterId", () => {
  assertEquals(
    artObjectPath({ ...base, kind: "character", characterId: "rex" }),
    "user-1/book-1/character-rex-v2.png",
  );
});

Deno.test("artObjectPath builds a plate path from the page index", () => {
  assertEquals(
    artObjectPath({ ...base, kind: "plate", pageIndex: 0 }),
    "user-1/book-1/plate-0-v2.png",
  );
});

Deno.test("artObjectPath builds a cutout path from character and page index", () => {
  assertEquals(
    artObjectPath({ ...base, kind: "cutout", characterId: "rex", pageIndex: 4 }),
    "user-1/book-1/cutout-rex-4-v2.png",
  );
});

Deno.test("artObjectPath always starts with the caller's own userId prefix", () => {
  const path = artObjectPath({ ...base, kind: "page", pageIndex: 0 });
  assertEquals(path.startsWith("user-1/"), true);
});

Deno.test("artObjectPath rejects a page kind with no pageIndex", () => {
  const error = assertThrows(
    () => artObjectPath({ ...base, kind: "page" }),
    PopError,
  );
  assertEquals(error.code, "bad_request");
});

Deno.test("artObjectPath rejects a character kind with no characterId", () => {
  assertThrows(() => artObjectPath({ ...base, kind: "character" }), PopError);
});

Deno.test("artObjectPath rejects a cutout kind missing either id", () => {
  assertThrows(() => artObjectPath({ ...base, kind: "cutout", pageIndex: 1 }), PopError);
  assertThrows(() => artObjectPath({ ...base, kind: "cutout", characterId: "rex" }), PopError);
});

Deno.test("artObjectPath builds a drawing path from characterId, with no page index", () => {
  assertEquals(
    artObjectPath({ ...base, kind: "drawing", characterId: "rex" }),
    "user-1/book-1/drawing-rex-v2.png",
  );
});

Deno.test("artObjectPath rejects a drawing kind with no characterId", () => {
  assertThrows(() => artObjectPath({ ...base, kind: "drawing" }), PopError);
});
