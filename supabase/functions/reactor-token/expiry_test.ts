import { assertEquals } from "jsr:@std/assert@1";
import { tokenExpiresAt } from "./expiry.ts";

// The app reads `expiresAt` as Unix seconds (ReactorMintResponse); this function
// used to send milliseconds, so the app thought the token lasted for millennia.
Deno.test("tokenExpiresAt is in Unix seconds, one TTL after now", () => {
  assertEquals(tokenExpiresAt(1_790_000_000_500, 3600), 1_790_003_600);
});

Deno.test("tokenExpiresAt rounds a partial second down", () => {
  assertEquals(tokenExpiresAt(1_999, 1), 2);
});
