import { assertEquals } from "jsr:@std/assert@1";
import { gateQuestion, questionTexts } from "./question_gate.ts";
import { NO_QUESTION, type PageQuestion } from "./question_plan.ts";
import type { SafetyDeps } from "./safety.ts";

const question: PageQuestion = {
  question: "Will Rex look under the bed or in the garden?",
  questionKind: "choice",
  choices: [
    { label: "Under the bed", symbol: "house.fill", direction: "Rex peeks under the bed.", followsPath: true },
    { label: "In the garden", symbol: "leaf.fill", direction: "Rex hops out to the garden.", followsPath: false },
  ],
};

function countingSafety(flagged: string[] = [], rubricSafe = true) {
  const calls = { moderate: [] as string[], rubric: 0 };
  const safety: SafetyDeps = {
    moderateText: async (text) => {
      calls.moderate.push(text);
      return { flagged: flagged.includes(text), categories: [] };
    },
    checkRubric: async () => {
      calls.rubric += 1;
      return { safe: rubricSafe, reason: rubricSafe ? "" : "too scary" };
    },
  };
  return { safety, calls };
}

Deno.test("questionTexts lists the ask, every label and every direction", () => {
  assertEquals(questionTexts(question), [
    "Will Rex look under the bed or in the garden?",
    "Under the bed",
    "In the garden",
    "Rex peeks under the bed.",
    "Rex hops out to the garden.",
  ]);
});

Deno.test("gateQuestion passes a safe question unchanged, moderating every text and running one rubric check", async () => {
  const { safety, calls } = countingSafety();
  const result = await gateQuestion(question, "early_reader", "en", ["Maya"], safety);
  assertEquals(result.question, question);
  assertEquals(calls.moderate.length, 5);
  assertEquals(calls.rubric, 1);
});

Deno.test("gateQuestion drops the whole question when one direction is flagged or the rubric fails", async () => {
  const flagged = await gateQuestion(question, "early_reader", "en", ["Maya"], countingSafety(["Rex hops out to the garden."]).safety);
  assertEquals(flagged.question, NO_QUESTION);
  const rubric = await gateQuestion(question, "early_reader", "en", ["Maya"], countingSafety([], false).safety);
  assertEquals(rubric.question, NO_QUESTION);
});

Deno.test("gateQuestion allows the kid's own non-Latin name but not another script", async () => {
  const named = { ...question, question: "Where will 李明 look?" };
  assertEquals((await gateQuestion(named, "reader", "en", ["李明"], countingSafety().safety)).question, named);
  const leaked = { ...question, question: "Где Rex?" };
  assertEquals((await gateQuestion(leaked, "reader", "en", ["Maya"], countingSafety().safety)).question, NO_QUESTION);
});

Deno.test("gateQuestion makes no network call for an empty question", async () => {
  const { safety, calls } = countingSafety();
  const result = await gateQuestion(NO_QUESTION, "listener", "en", ["Maya"], safety);
  assertEquals(result, { question: NO_QUESTION, safetyMs: 0 });
  assertEquals(calls, { moderate: [], rubric: 0 });
});
