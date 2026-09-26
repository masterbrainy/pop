import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

Deno.test("requestSchema accepts list", () => {
  assert(requestSchema.safeParse({ action: "list" }).success);
});

Deno.test("requestSchema accepts kill", () => {
  assert(requestSchema.safeParse({ action: "kill" }).success);
});

Deno.test("requestSchema rejects an unknown action", () => {
  assertFalse(requestSchema.safeParse({ action: "wipe" }).success);
});
