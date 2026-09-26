import { assertEquals } from "jsr:@std/assert@1";
import { normalizeQuestion, questionKindFor, type ModelQuestion } from "./question_plan.ts";
import { DEFAULT_CHOICE_SYMBOL } from "./choice_symbols.ts";

// --- questionKindFor ---

Deno.test("questionKindFor gives a listener 2 choices on pages 1 and 3 only, talk-only elsewhere", () => {
  assertEquals(questionKindFor("listener", 0, 6), { kind: "talkOnly", choiceCount: 0 });
  assertEquals(questionKindFor("listener", 1, 6), { kind: "choice", choiceCount: 2 });
  assertEquals(questionKindFor("listener", 2, 6), { kind: "talkOnly", choiceCount: 0 });
  assertEquals(questionKindFor("listener", 3, 6), { kind: "choice", choiceCount: 2 });
  assertEquals(questionKindFor("listener", 4, 6), { kind: "talkOnly", choiceCount: 0 });
});

Deno.test("questionKindFor never gives a listener choices on the ending, even on page 3", () => {
  assertEquals(questionKindFor("listener", 3, 4), { kind: "talkOnly", choiceCount: 0 });
  assertEquals(questionKindFor("listener", 1, 2), { kind: "talkOnly", choiceCount: 0 });
});

Deno.test("questionKindFor gives an early reader 3 choices on every page but the ending", () => {
  assertEquals(questionKindFor("early_reader", 0, 6), { kind: "choice", choiceCount: 3 });
  assertEquals(questionKindFor("early_reader", 4, 6), { kind: "choice", choiceCount: 3 });
  assertEquals(questionKindFor("early_reader", 5, 6), { kind: "talkOnly", choiceCount: 0 });
});

Deno.test("questionKindFor gives a reader an open question with 3 choices, talk-only on the ending", () => {
  assertEquals(questionKindFor("reader", 0, 6), { kind: "open", choiceCount: 3 });
  assertEquals(questionKindFor("reader", 5, 6), { kind: "talkOnly", choiceCount: 0 });
});

Deno.test("questionKindFor treats an unknown path length as not the ending", () => {
  assertEquals(questionKindFor("early_reader", 0, null), { kind: "choice", choiceCount: 3 });
  assertEquals(questionKindFor("listener", 1, 0), { kind: "choice", choiceCount: 2 });
});

// --- normalizeQuestion ---

function choice(label: string, followsPath = false, overrides: Partial<ModelQuestion["choices"][number]> = {}) {
  return { label, symbol: "star.fill", direction: `${label} happens next.`, followsPath, ...overrides };
}

const threeChoices: ModelQuestion = {
  ask: "  Where will Rex look next?  ",
  kind: "choice",
  choices: [choice("Under the bed", true), choice("In the garden"), choice("Up a tree")],
};

Deno.test("normalizeQuestion keeps a well-formed choice question, trimmed", () => {
  const result = normalizeQuestion(threeChoices, { kind: "choice", choiceCount: 3 }, false);
  assertEquals(result.question, "Where will Rex look next?");
  assertEquals(result.questionKind, "choice");
  assertEquals(result.choices.length, 3);
  assertEquals(result.choices.map((c) => c.followsPath), [true, false, false]);
});

Deno.test("normalizeQuestion makes the ending talk-only with no choices", () => {
  const result = normalizeQuestion(threeChoices, { kind: "choice", choiceCount: 3 }, true);
  assertEquals(result.questionKind, "talkOnly");
  assertEquals(result.choices, []);
  assertEquals(result.question, "Where will Rex look next?");
});

Deno.test("normalizeQuestion follows the plan's kind, not the model's", () => {
  const talk = normalizeQuestion(threeChoices, { kind: "talkOnly", choiceCount: 0 }, false);
  assertEquals(talk.questionKind, "talkOnly");
  assertEquals(talk.choices, []);

  const open = normalizeQuestion(threeChoices, { kind: "open", choiceCount: 3 }, false);
  assertEquals(open.questionKind, "open");
  assertEquals(open.choices.length, 3);
});

Deno.test("normalizeQuestion truncates to the plan's choice count", () => {
  const result = normalizeQuestion(threeChoices, { kind: "choice", choiceCount: 2 }, false);
  assertEquals(result.choices.map((c) => c.label), ["Under the bed", "In the garden"]);
});

Deno.test("normalizeQuestion keeps the followsPath choice when truncating would cut it", () => {
  const question: ModelQuestion = {
    ask: "What next?",
    kind: "choice",
    choices: [choice("A"), choice("B"), choice("C", true)],
  };
  const result = normalizeQuestion(question, { kind: "choice", choiceCount: 2 }, false);
  assertEquals(result.choices.map((c) => c.label), ["A", "C"]);
  assertEquals(result.choices.map((c) => c.followsPath), [false, true]);
});

Deno.test("normalizeQuestion keeps at most one followsPath (the first true)", () => {
  const question: ModelQuestion = {
    ask: "What next?",
    kind: "choice",
    choices: [choice("A"), choice("B", true), choice("C", true)],
  };
  const result = normalizeQuestion(question, { kind: "choice", choiceCount: 3 }, false);
  assertEquals(result.choices.map((c) => c.followsPath), [false, true, false]);
});

Deno.test("normalizeQuestion drops choices with an empty label or direction, or a direction over 120 characters", () => {
  const question: ModelQuestion = {
    ask: "What next?",
    kind: "choice",
    choices: [
      choice("   "),
      choice("B", false, { direction: "  " }),
      choice("C", false, { direction: "x".repeat(121) }),
      choice(" Keep me ", false, { direction: " Rex finds his ball. " }),
      choice("Me too"),
    ],
  };
  const result = normalizeQuestion(question, { kind: "choice", choiceCount: 3 }, false);
  assertEquals(result.choices.map((c) => c.label), ["Keep me", "Me too"]);
  assertEquals(result.choices[0].direction, "Rex finds his ball.");
});

Deno.test("normalizeQuestion turns a choice question with fewer than 2 valid choices into talk-only", () => {
  const question: ModelQuestion = { ask: "What next?", kind: "choice", choices: [choice("Only one", true), choice("")] };
  const result = normalizeQuestion(question, { kind: "choice", choiceCount: 2 }, false);
  assertEquals(result.questionKind, "talkOnly");
  assertEquals(result.choices, []);
  assertEquals(result.question, "What next?");
});

Deno.test("normalizeQuestion keeps an open question with no usable choices, but drops a lone choice", () => {
  const question: ModelQuestion = { ask: "What's the plan?", kind: "open", choices: [choice("Only one")] };
  const result = normalizeQuestion(question, { kind: "open", choiceCount: 3 }, false);
  assertEquals(result.questionKind, "open");
  assertEquals(result.choices, []);
});

Deno.test("normalizeQuestion maps an unknown symbol to the default symbol", () => {
  const question: ModelQuestion = {
    ask: "What next?",
    kind: "choice",
    choices: [choice("A", true, { symbol: "not.a.symbol" }), choice("B")],
  };
  const result = normalizeQuestion(question, { kind: "choice", choiceCount: 2 }, false);
  assertEquals(result.choices[0].symbol, DEFAULT_CHOICE_SYMBOL);
  assertEquals(result.choices[1].symbol, "star.fill");
});

Deno.test("normalizeQuestion with an empty ask returns no question, no kind and no choices", () => {
  const result = normalizeQuestion({ ...threeChoices, ask: "   " }, { kind: "choice", choiceCount: 3 }, false);
  assertEquals(result, { question: "", choices: [] });
  assertEquals("questionKind" in result, false);
});
