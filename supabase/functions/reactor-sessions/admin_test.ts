import { assert, assertThrows } from "jsr:@std/assert@1";
import { checkAdminHeader } from "./admin.ts";
import { isPopError } from "../_shared/errors.ts";

Deno.test("checkAdminHeader passes when the header matches the secret", () => {
  checkAdminHeader("correct-secret", "correct-secret");
});

Deno.test("checkAdminHeader throws forbidden when the header is wrong", () => {
  assertThrows(
    () => checkAdminHeader("wrong-secret", "correct-secret"),
    Error,
  );
  try {
    checkAdminHeader("wrong-secret", "correct-secret");
    assert(false, "expected checkAdminHeader to throw");
  } catch (error) {
    assert(isPopError(error));
    assert(error.code === "forbidden");
  }
});

Deno.test("checkAdminHeader throws forbidden when the header is missing", () => {
  try {
    checkAdminHeader(null, "correct-secret");
    assert(false, "expected checkAdminHeader to throw");
  } catch (error) {
    assert(isPopError(error));
    assert(error.code === "forbidden");
  }
});
