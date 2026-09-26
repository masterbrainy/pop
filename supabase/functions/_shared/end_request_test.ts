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

Deno.test("detectsEndRequest ignores 'the end of' something in an everyday direction (R-43)", () => {
  assertFalse(detectsEndRequest("Let us go to the end of the rainbow"));
  assertFalse(detectsEndRequest("They walk to the end of the garden"));
  assertFalse(detectsEndRequest("At the end of the day the fox goes home"));
  assertFalse(detectsEndRequest("the end of the tunnel is bright"));
  assertFalse(detectsEndRequest("Put a treasure chest at the end."));
});

Deno.test("detectsEndRequest ignores a direction that says not to end yet (R-43)", () => {
  assertFalse(detectsEndRequest("Don't finish the story yet, add a dragon."));
  assertFalse(detectsEndRequest("Please do not end the story now."));
});

Deno.test("detectsEndRequest still hears 'the end' said on its own", () => {
  assert(detectsEndRequest("The end!"));
  assert(detectsEndRequest("and they lived happily, and the end"));
  assert(detectsEndRequest("Time for bed. The end."));
});
