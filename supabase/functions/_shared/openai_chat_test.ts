import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { z } from "npm:zod@3.23.8";
import { parseModelJSON } from "./openai_chat.ts";
import { PopError } from "./errors.ts";

const schema = z.object({ title: z.string() });

Deno.test("parseModelJSON parses and validates well-formed JSON", () => {
  const result = parseModelJSON('{"title": "Rex Learns to Share"}', schema);
  assertEquals(result, { title: "Rex Learns to Share" });
});

Deno.test("parseModelJSON raises an upstream PopError on invalid JSON text", () => {
  const error = assertThrows(() => parseModelJSON("not json", schema), PopError);
  assertEquals(error.code, "upstream");
});

Deno.test("parseModelJSON raises an upstream PopError when the shape doesn't match", () => {
  const error = assertThrows(() => parseModelJSON('{"nope": 1}', schema), PopError);
  assertEquals(error.code, "upstream");
});
