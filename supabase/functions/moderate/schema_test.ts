import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

Deno.test("requestSchema accepts a text body", () => {
  const result = requestSchema.safeParse({ text: "hello there" });
  assert(result.success);
});

Deno.test("requestSchema accepts an image body", () => {
  const result = requestSchema.safeParse({ imageBase64: "aGVsbG8=", mimeType: "image/png" });
  assert(result.success);
});

Deno.test("requestSchema rejects an empty text", () => {
  const result = requestSchema.safeParse({ text: "" });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects a body that is neither shape", () => {
  const result = requestSchema.safeParse({ foo: "bar" });
  assertFalse(result.success);
});

Deno.test("requestSchema rejects an image body missing mimeType", () => {
  const result = requestSchema.safeParse({ imageBase64: "aGVsbG8=" });
  assertFalse(result.success);
});
