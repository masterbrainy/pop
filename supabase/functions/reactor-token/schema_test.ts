import { assert, assertFalse } from "jsr:@std/assert@1";
import { requestSchema } from "./schema.ts";

Deno.test("requestSchema accepts mint", () => {
  assert(requestSchema.safeParse({ action: "mint" }).success);
});

Deno.test("requestSchema accepts report with a sessionId", () => {
  assert(requestSchema.safeParse({ action: "report", sessionId: "sess_123" }).success);
});

Deno.test("requestSchema rejects report without a sessionId", () => {
  assertFalse(requestSchema.safeParse({ action: "report" }).success);
});

Deno.test("requestSchema accepts cleanup", () => {
  assert(requestSchema.safeParse({ action: "cleanup" }).success);
});

Deno.test("requestSchema rejects an unknown action", () => {
  assertFalse(requestSchema.safeParse({ action: "destroy" }).success);
});
