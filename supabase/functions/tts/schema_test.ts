import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

Deno.test("requestSchema accepts text with an explicit voice", () => {
  const result = requestSchema.safeParse({ text: "Hello!", voice: "shimmer" });
  assert(result.success);
  if (result.success) assertEquals(result.data.voice, "shimmer");
});

Deno.test("requestSchema defaults voice to alloy", () => {
  const result = requestSchema.safeParse({ text: "Hello!" });
  assert(result.success);
  if (result.success) assertEquals(result.data.voice, "alloy");
});

Deno.test("requestSchema rejects empty text", () => {
  assertFalse(requestSchema.safeParse({ text: "" }).success);
});

Deno.test("requestSchema rejects missing text", () => {
  assertFalse(requestSchema.safeParse({ voice: "alloy" }).success);
});
