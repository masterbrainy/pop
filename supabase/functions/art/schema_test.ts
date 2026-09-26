import { assert, assertFalse } from "jsr:@std/assert@1";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { MAX_DRAWING_BYTES, requestSchema } from "./schema.ts";

const bookId = "123e4567-e89b-12d3-a456-426614174000";

function pngBase64(byteLength: number): string {
  const bytes = new Uint8Array(byteLength);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  return encodeBase64(bytes);
}

const validDrawing = pngBase64(64);

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

Deno.test("requestSchema accepts a drawing request with a valid PNG and characterId", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    characterId: "rex",
    version: 1,
    prompt: "a purple cat with wings",
    drawing: validDrawing,
  });
  assert(result.success);
});

Deno.test("requestSchema accepts a drawing request with a valid JPEG", () => {
  const bytes = new Uint8Array(64);
  bytes.set([0xff, 0xd8, 0xff, 0xe0], 0);
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    characterId: "rex",
    version: 1,
    prompt: "a purple cat with wings",
    drawing: encodeBase64(bytes),
  });
  assert(result.success);
});

Deno.test("requestSchema rejects a drawing request missing the drawing field", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    characterId: "rex",
    version: 1,
    prompt: "a purple cat with wings",
  });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a drawing request missing characterId", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    version: 1,
    prompt: "a purple cat with wings",
    drawing: validDrawing,
  });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a drawing that isn't valid base64", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    characterId: "rex",
    version: 1,
    prompt: "a purple cat with wings",
    drawing: "not-valid-base64!!!",
  });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a drawing over MAX_DRAWING_BYTES decoded", () => {
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    characterId: "rex",
    version: 1,
    prompt: "a purple cat with wings",
    drawing: pngBase64(MAX_DRAWING_BYTES + 1),
  });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a drawing that decodes to neither PNG nor JPEG", () => {
  const bytes = new Uint8Array(64);
  bytes.set([0x47, 0x49, 0x46, 0x38, 0x39, 0x61], 0); // GIF signature
  const result = requestSchema.safeParse({
    bookId,
    kind: "drawing",
    characterId: "rex",
    version: 1,
    prompt: "a purple cat with wings",
    drawing: encodeBase64(bytes),
  });
  assertFalse(result.success);
});
