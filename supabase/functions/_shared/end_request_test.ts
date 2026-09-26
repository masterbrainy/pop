import { assert, assertFalse } from "jsr:@std/assert@1";
import { detectsEndRequest } from "./end_request.ts";

Deno.test("detectsEndRequest matches the three ending-eval directions (R-35 d)", () => {
  assert(detectsEndRequest("And they all went to sleep, the end."));
  assert(detectsEndRequest("Let's wrap up the story now with a happy ending."));
  assert(detectsEndRequest("Let's finish the story here with a proper ending."));
});

Deno.test("detectsEndRequest matches a few other common phrasings", () => {
  assert(detectsEndRequest("Can we end the story now?"));
  assert(detectsEndRequest("Please finish this story."));
  assert(detectsEndRequest("Let's stop our story here."));
});

Deno.test("detectsEndRequest is case-insensitive", () => {
  assert(detectsEndRequest("THE END"));
});

Deno.test("detectsEndRequest does not match an ordinary direction", () => {
  assertFalse(detectsEndRequest("Make the dragon purple."));
  assertFalse(detectsEndRequest("Give her a talking parrot companion."));
});

Deno.test("detectsEndRequest treats empty text as not an end request", () => {
  assertFalse(detectsEndRequest(""));
  assertFalse(detectsEndRequest("   "));
});
