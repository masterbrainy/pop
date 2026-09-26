import { assertEquals } from "jsr:@std/assert@1";
import { buildMintTokenRequestBody } from "./reactor_client.ts";

Deno.test("buildMintTokenRequestBody matches the Reactor /tokens contract exactly", () => {
  assertEquals(buildMintTokenRequestBody(), {
    expires_after: 3600,
    authorization_details: [{
      type: "session",
      resources: { models: { match: ["reactor/visko-orbis-stable"] } },
      constraints: { max_sessions: 2 },
    }],
  });
});

Deno.test("buildMintTokenRequestBody honors custom session count and expiry", () => {
  const body = buildMintTokenRequestBody(1, 60);
  assertEquals(body.expires_after, 60);
  assertEquals(body.authorization_details[0].constraints.max_sessions, 1);
});
