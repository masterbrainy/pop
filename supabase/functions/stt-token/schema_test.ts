import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

Deno.test("requestSchema accepts an empty body", () => {
  assert(requestSchema.safeParse({}).success);
});

Deno.test("requestSchema rejects extra fields", () => {
  assertFalse(requestSchema.safeParse({ extra: true }).success);
});
