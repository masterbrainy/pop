import { assertEquals } from "jsr:@std/assert@1";
import { describeGeminiError } from "./gemini_error.ts";

Deno.test("describeGeminiError keeps Google's status and message", () => {
  const body = JSON.stringify({ error: { code: 402, status: "FAILED_PRECONDITION", message: "Your prepayment credits are depleted." } });
  assertEquals(describeGeminiError(402, body), "402 FAILED_PRECONDITION: Your prepayment credits are depleted.");
});

Deno.test("describeGeminiError falls back to the HTTP status for a body that isn't Google's JSON", () => {
  assertEquals(describeGeminiError(503, "<html>busy</html>"), "503");
});

Deno.test("describeGeminiError shortens a long message", () => {
  const body = JSON.stringify({ error: { status: "X", message: "a".repeat(500) } });
  assertEquals(describeGeminiError(429, body).length <= 4 + 2 + 1 + 200 + 1, true);
});
