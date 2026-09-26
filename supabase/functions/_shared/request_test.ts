import { assert, assertEquals } from "jsr:@std/assert@1";
import { z } from "npm:zod@3.23.8";
import { parseRequest } from "./request.ts";
import { PopError } from "./errors.ts";

const schema = z.object({ text: z.string().min(1) });

function req(body: unknown) {
  return new Request("https://example.com/fn", {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

Deno.test("parseRequest returns the validated, typed body", async () => {
  const result = await parseRequest(req({ text: "hello" }), schema);
  assertEquals(result, { text: "hello" });
});

Deno.test("parseRequest raises bad_request on malformed JSON", async () => {
  try {
    await parseRequest(req("not json"), schema);
    assert(false, "expected parseRequest to throw");
  } catch (error) {
    assert(error instanceof PopError);
    assertEquals(error.code, "bad_request");
  }
});

Deno.test("parseRequest raises bad_request with a field path when validation fails", async () => {
  try {
    await parseRequest(req({ text: "" }), schema);
    assert(false, "expected parseRequest to throw");
  } catch (error) {
    assert(error instanceof PopError);
    assertEquals(error.code, "bad_request");
    assert((error as PopError).message.startsWith("text:"));
  }
});
