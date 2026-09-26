import { assertEquals } from "jsr:@std/assert@1";
import { runSafetyGate, type SafetyDeps } from "./safety.ts";

function fakeDeps(overrides: Partial<SafetyDeps> = {}): SafetyDeps {
  return {
    moderateText: async () => ({ flagged: false, categories: [] }),
    checkRubric: async () => ({ safe: true, reason: "" }),
    ...overrides,
  };
}

Deno.test("runSafetyGate treats no text as trivially safe and skips network calls", async () => {
  let moderateCalled = false;
  const deps = fakeDeps({
    moderateText: async () => {
      moderateCalled = true;
      return { flagged: false, categories: [] };
    },
  });
  const verdict = await runSafetyGate(["", "   "], "reader", deps);
  assertEquals(verdict, { safe: true, reason: "", flaggedCategories: [] });
  assertEquals(moderateCalled, false);
});

Deno.test("runSafetyGate passes when moderation and the rubric both pass", async () => {
  const verdict = await runSafetyGate(["A friendly dragon shares a cookie."], "listener", fakeDeps());
  assertEquals(verdict.safe, true);
});

Deno.test("runSafetyGate fails when moderation flags any text, and lists categories", async () => {
  const deps = fakeDeps({
    moderateText: async (text) =>
      text.includes("scary")
        ? { flagged: true, categories: ["violence"] }
        : { flagged: false, categories: [] },
  });
  const verdict = await runSafetyGate(["ok text", "something scary"], "reader", deps);
  assertEquals(verdict.safe, false);
  assertEquals(verdict.flaggedCategories, ["violence"]);
  assertEquals(verdict.reason, "Flagged by content moderation.");
});

Deno.test("runSafetyGate fails when the rubric fails, even if moderation passes", async () => {
  const deps = fakeDeps({
    checkRubric: async () => ({ safe: false, reason: "Too scary for a Listener" }),
  });
  const verdict = await runSafetyGate(["a tense moment"], "listener", deps);
  assertEquals(verdict.safe, false);
  assertEquals(verdict.reason, "Too scary for a Listener");
});

Deno.test("runSafetyGate falls back to a generic reason when the rubric gives none", async () => {
  const deps = fakeDeps({ checkRubric: async () => ({ safe: false, reason: "" }) });
  const verdict = await runSafetyGate(["text"], "reader", deps);
  assertEquals(verdict.reason, "Failed the kid-safety rubric.");
});

Deno.test("runSafetyGate only sends non-empty texts to moderation", async () => {
  const seen: string[] = [];
  const deps = fakeDeps({
    moderateText: async (text) => {
      seen.push(text);
      return { flagged: false, categories: [] };
    },
  });
  await runSafetyGate(["  ", "real text", ""], "reader", deps);
  assertEquals(seen, ["real text"]);
});
