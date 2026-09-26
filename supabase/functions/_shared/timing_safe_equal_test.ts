import { assert, assertFalse } from "jsr:@std/assert@1";
import { timingSafeEqualStrings } from "./timing_safe_equal.ts";

Deno.test("timingSafeEqualStrings is true for identical strings", () => {
  assert(timingSafeEqualStrings("super-secret-value", "super-secret-value"));
});

Deno.test("timingSafeEqualStrings is false for different strings of the same length", () => {
  assertFalse(timingSafeEqualStrings("super-secret-value", "super-secret-valuf"));
});

Deno.test("timingSafeEqualStrings is false for different lengths", () => {
  assertFalse(timingSafeEqualStrings("short", "much-longer-value"));
});

Deno.test("timingSafeEqualStrings treats empty strings as equal to each other only", () => {
  assert(timingSafeEqualStrings("", ""));
  assertFalse(timingSafeEqualStrings("", "x"));
});
