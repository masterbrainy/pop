import { assertEquals } from "jsr:@std/assert@1";
import { PopError } from "./errors.ts";
import { servePop } from "./handler.ts";

function postRequest(body: unknown = {}) {
  return new Request("https://example.com/fn", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

Deno.test("servePop returns the envelope-wrapped data on success", async () => {
  const res = await servePop(postRequest(), "test-fn", async () => ({
    data: { hello: "world" },
  }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true, data: { hello: "world" } });
});

Deno.test("servePop honors a custom success status", async () => {
  const res = await servePop(postRequest(), "test-fn", async () => ({
    data: {},
    status: 201,
  }));
  assertEquals(res.status, 201);
});

Deno.test("servePop turns a thrown PopError into the matching error envelope", async () => {
  const res = await servePop(postRequest(), "test-fn", async () => {
    throw new PopError("rate_limited", "slow down");
  });
  assertEquals(res.status, 429);
  assertEquals(await res.json(), {
    ok: false,
    error: { code: "rate_limited", message: "slow down" },
  });
});

Deno.test("servePop hides unexpected error details behind a generic internal error", async () => {
  const res = await servePop(postRequest(), "test-fn", async () => {
    throw new Error("leaky stack trace with secret token abc123");
  });
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error.code, "internal");
  assertEquals(body.error.message.includes("secret"), false);
});

Deno.test("servePop answers OPTIONS with a CORS preflight before touching the handler", async () => {
  let called = false;
  const res = await servePop(
    new Request("https://example.com/fn", { method: "OPTIONS" }),
    "test-fn",
    async () => {
      called = true;
      return { data: {} };
    },
  );
  assertEquals(res.status, 200);
  assertEquals(called, false);
});

Deno.test("servePop rejects non-POST, non-OPTIONS methods as bad_request", async () => {
  const res = await servePop(
    new Request("https://example.com/fn", { method: "GET" }),
    "test-fn",
    async () => ({ data: {} }),
  );
  assertEquals(res.status, 400);
});
