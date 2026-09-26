import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

const bookId = "123e4567-e89b-12d3-a456-426614174000";

Deno.test("requestSchema accepts a well-formed request", () => {
  const result = requestSchema.safeParse({
    bookId,
    pageIndex: 0,
    text: "Rex found a shiny rock.",
    stillPath: "u/b/page-0-v1.png",
  });
  assert(result.success);
});

Deno.test("requestSchema rejects a missing stillPath", () => {
  const result = requestSchema.safeParse({ bookId, pageIndex: 0, text: "Rex found a rock." });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a negative pageIndex", () => {
  const result = requestSchema.safeParse({
    bookId,
    pageIndex: -1,
    text: "x",
    stillPath: "u/b/page-0-v1.png",
  });
  assertFalse(result.success);
});
