import { assertEquals } from "jsr:@std/assert@1";
import { errorResponse, okResponse, statusForCode } from "./envelope.ts";

Deno.test("okResponse returns ok:true with the data payload and status 200", async () => {
  const res = okResponse({ title: "Rex Learns to Share" });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Type"), "application/json");
  const body = await res.json();
  assertEquals(body, { ok: true, data: { title: "Rex Learns to Share" } });
});

Deno.test("okResponse accepts a custom status", async () => {
  const res = okResponse({ created: true }, 201);
  assertEquals(res.status, 201);
});

Deno.test("errorResponse maps each code to its HTTP status", async () => {
  const cases: [Parameters<typeof errorResponse>[0], number][] = [
    ["bad_request", 400],
    ["unauthorized", 401],
    ["forbidden", 403],
    ["unsafe", 422],
    ["rate_limited", 429],
    ["upstream", 502],
    ["internal", 500],
  ];
  for (const [code, status] of cases) {
    const res = errorResponse(code, "message");
    assertEquals(res.status, status);
    assertEquals(statusForCode(code), status);
    const body = await res.json();
    assertEquals(body, { ok: false, error: { code, message: "message" } });
  }
});

Deno.test("every response carries CORS headers", () => {
  const res = okResponse({});
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});
