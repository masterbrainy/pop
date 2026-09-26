import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

const bookId = "123e4567-e89b-12d3-a456-426614174000";

Deno.test("requestSchema accepts a page request with pageIndex", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "page",
    pageIndex: 0,
    version: 1,
    prompt: "A dinosaur in a meadow",
    characters: [],
  });
  assert(result.success);
});

Deno.test("requestSchema rejects a page request missing pageIndex", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "page",
    version: 1,
    prompt: "A dinosaur in a meadow",
  });
  assertFalse(result.success);
});

Deno.test("requestSchema accepts a cover request with no pageIndex", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "cover",
    version: 1,
    prompt: "The whole gang on an adventure",
  });
  assert(result.success);
});

Deno.test("requestSchema requires characterId for character and cutout kinds", () => {
  assertFalse(
    requestSchema.safeParse({ bookId, kind: "character", version: 1, prompt: "Rex" }).success,
  );
  assertFalse(
    requestSchema.safeParse({ bookId, kind: "cutout", pageIndex: 0, version: 1, prompt: "Rex waving" }).success,
  );
  assert(
    requestSchema.safeParse({
      bookId,
      kind: "cutout",
      pageIndex: 0,
      characterId: "rex",
      version: 1,
      prompt: "Rex waving",
    }).success,
  );
});

Deno.test("requestSchema rejects an unknown kind", () => {
  const result = requestSchema.safeParse({ bookId, kind: "sticker", version: 1, prompt: "x" });
  assertFalse(result.success);
});

Deno.test("requestSchema defaults characters to an empty array", () => {
  const result = requestSchema.safeParse({ bookId, kind: "cover", version: 1, prompt: "x" });
  assert(result.success);
  if (result.success) assert(Array.isArray(result.data.characters));
});
