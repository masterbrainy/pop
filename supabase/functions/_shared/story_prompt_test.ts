import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  buildStoryPageSystemPrompt,
  buildStoryPathSystemPrompt,
  buildTitlePrompt,
  describeSetup,
  type StoryPagePromptInput,
  type StoryPathPromptInput,
} from "./story_prompt.ts";
import type { Kid, StoryBrief } from "./schemas.ts";

Deno.test("buildTitlePrompt orders pages by index and includes the setting and first name", () => {
  const prompt = buildTitlePrompt(
    { title: null, setting: "a quiet meadow", characters: [], directions: [], path: [] },
    [{ index: 1, text: "Page two text" }, { index: 0, text: "Page one text" }],
    "Sara",
  );
  const indexOfPageOne = prompt.indexOf("Page one text");
  const indexOfPageTwo = prompt.indexOf("Page two text");
  assert(indexOfPageOne < indexOfPageTwo);
  assert(prompt.includes("Sara"));
  assert(prompt.includes("a quiet meadow"));
});

function basePathInput(overrides: Partial<StoryPathPromptInput> = {}): StoryPathPromptInput {
  return {
    kid: { firstName: "Sara", readingLevel: "early_reader", interests: ["dinosaurs"] },
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible: { title: null, setting: "", characters: [], directions: [], path: [] },
    pages: [],
    index: 0,
    input: null,
    ...overrides,
  };
}

Deno.test("buildStoryPathSystemPrompt asks the model to plan about 5-8 beats ending the story", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("5 to 8"));
  assert(prompt.toLowerCase().includes("end the story"));
});

Deno.test("buildStoryPathSystemPrompt lists earlier beats as fixed and never to change, at the start with none", () => {
  const withStart = buildStoryPathSystemPrompt(basePathInput());
  assertFalse(withStart.includes("never change these"));

  const withKept = buildStoryPathSystemPrompt(
    basePathInput({ bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] }, index: 1 }),
  );
  assert(withKept.includes("never change these"));
  assert(withKept.includes("Beat 0"));
});

Deno.test("buildStoryPathSystemPrompt folds a direction into the prompt and asks to re-plan from index on, only when input is present", () => {
  const withoutDirection = buildStoryPathSystemPrompt(basePathInput());
  assert(withoutDirection.includes("Plan the path from the brief"));

  // A later direction: page 0 is already shown, so this re-plans from page 1.
  const withDirection = buildStoryPathSystemPrompt(
    basePathInput({
      index: 1,
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] },
      pages: [{ index: 0, text: "Sara finds a sleeping dragon." }],
      input: { kind: "typed", speaker: "parent", text: "wake the dragon up" },
    }),
  );
  assert(withDirection.includes("wake the dragon up"));
  assert(withDirection.includes("re-plan the path from page 1 on"));
});

// The app writes page 1 only once the parent speaks or types the first prompt:
// index 0, nothing shown yet, and input set. That's the story's opening idea,
// not a mid-story direction.
Deno.test("buildStoryPathSystemPrompt plans the whole path from the parent's opening idea, with the brief as background", () => {
  const prompt = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "speech", speaker: "parent", text: "a dragon who is scared of the dark" } }),
  );
  assert(prompt.includes(
    'The parent\'s opening idea for the story: "a dragon who is scared of the dark". Plan the whole path from it, with the brief as background.',
  ));
  assert(prompt.includes("Fold this opening idea into the bible's directions so it carries into every later page."));
  assertFalse(prompt.includes("A direction just came in"));
  assertFalse(prompt.includes("re-plan the path"));
  assertFalse(prompt.includes("Plan the path from the brief above."));
});

Deno.test("buildStoryPathSystemPrompt names the kid when the opening idea is the kid's", () => {
  const prompt = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "speech", speaker: "kid", text: "a unicorn at the beach" } }),
  );
  assert(prompt.includes('Sara\'s opening idea for the story: "a unicorn at the beach".'));
  assertFalse(prompt.includes("The parent's opening idea"));
});

Deno.test("buildStoryPathSystemPrompt never ends the story on page 1 because the opening idea mentions an ending", () => {
  const prompt = buildStoryPathSystemPrompt(
    basePathInput({
      input: { kind: "typed", speaker: "parent", text: "a bunny who finds a lost star, and we end the story with a bedtime hug" },
    }),
  );
  assertFalse(prompt.includes("the very last beat"));
  assertFalse(prompt.includes("unmistakable close"));
});

Deno.test("buildStoryPathSystemPrompt treats a blank opening input like the brief-only start", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({ input: { kind: "typed", speaker: "parent", text: "   " } }));
  assert(prompt.includes("Plan the path from the brief above."));
  assertFalse(prompt.includes("opening idea"));
});

Deno.test("buildStoryPathSystemPrompt asks for art prompts that name exactly the characters who appear", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("In artPrompt, name every character who appears by their bible name, and only those."));
});

Deno.test("buildStoryPageSystemPrompt asks for art prompts that name exactly the characters who appear", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("In artPrompt, name every character who appears by their bible name, and only those."));
});

Deno.test("buildStoryPathSystemPrompt never omits the personal-details or safety rubric instructions", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("surnames"));
  assert(prompt.includes("Kid-safety rubric"));
});

// R-42/ending-eval product rule: a direction that explicitly asks to end the
// story now overrides the usual "about 5 to 8 beats" guidance for that turn.
Deno.test("buildStoryPathSystemPrompt tells the model to end at this page when the direction asks to end now", () => {
  const withEndRequest = buildStoryPathSystemPrompt(
    basePathInput({
      index: 1,
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] },
      input: { kind: "typed", speaker: "parent", text: "Let's finish the story here with a proper ending." },
    }),
  );
  assert(withEndRequest.includes("make page 1 the very last beat"));
  assert(withEndRequest.includes('set "isEnding" to true'));
});

Deno.test("buildStoryPathSystemPrompt does not add the end-now instruction for an ordinary direction", () => {
  const withOrdinaryDirection = buildStoryPathSystemPrompt(
    basePathInput({ input: { kind: "typed", speaker: "parent", text: "wake the dragon up" } }),
  );
  assertFalse(withOrdinaryDirection.includes("the very last beat"));
});

Deno.test("buildStoryPathSystemPrompt suggests concrete closing images for the path's last beat generally", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("safe and happy"));
  assert(prompt.includes("drifting off to sleep"));
});

Deno.test("buildStoryPathSystemPrompt gives the prescriptive ending-close instruction when the direction asks to end now", () => {
  const withEndRequest = buildStoryPathSystemPrompt(
    basePathInput({
      index: 1,
      kid: { firstName: "Sara", readingLevel: "reader", interests: ["dinosaurs"] },
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0"] },
      input: { kind: "typed", speaker: "parent", text: "Let's finish the story here with a proper ending." },
    }),
  );
  assert(withEndRequest.includes("unmistakable close"));
  assert(withEndRequest.includes("safe and back home"));
  assert(withEndRequest.includes('the words "The end."'));
});

Deno.test("buildStoryPathSystemPrompt tells the model to write only in the brief's language", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput());
  assert(prompt.includes("only in English"));
  assert(prompt.includes("Never mix in a word, phrase or script from any other language"));
});

function basePageInput(overrides: Partial<StoryPagePromptInput> = {}): StoryPagePromptInput {
  return {
    kid: { firstName: "Sara", readingLevel: "early_reader", interests: ["dinosaurs"] },
    brief: { interests: ["dinosaurs"], realMoment: null, teach: null, language: "en" },
    settings: { avoidTopics: [] },
    bible: { title: null, setting: "", characters: [], directions: [], path: ["Sara finds a red kite in the meadow."] },
    pages: [],
    index: 0,
    ...overrides,
  };
}

Deno.test("buildStoryPageSystemPrompt writes from the existing beat at bible.path[index]", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("Sara finds a red kite in the meadow."));
  assert(prompt.includes("do not invent a different moment"));
});

Deno.test("buildStoryPageSystemPrompt never omits the personal-details or safety rubric instructions", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("surnames"));
  assert(prompt.includes("Kid-safety rubric"));
});

Deno.test("buildStoryPageSystemPrompt tells the model to write only in the brief's language", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput());
  assert(prompt.includes("only in English"));
  assert(prompt.includes("Never mix in a word, phrase or script from any other language"));
});

Deno.test("buildStoryPageSystemPrompt tells the model to write a clear ending only on the path's last index", () => {
  const notLastPage = buildStoryPageSystemPrompt(
    basePageInput({ bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] }, index: 0 }),
  );
  assertFalse(notLastPage.includes("path's last page"));

  const lastPage = buildStoryPageSystemPrompt(
    basePageInput({ bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] }, index: 1 }),
  );
  assert(lastPage.includes("path's last page"));
  assert(lastPage.includes("unmistakable close"));
  assert(lastPage.includes('the words "The end."'));
});

Deno.test("buildStoryPageSystemPrompt asks for one of the eval's exact closing phrases at the reader level", () => {
  const lastPage = buildStoryPageSystemPrompt(
    basePageInput({
      kid: { firstName: "Sara", readingLevel: "reader", interests: ["dinosaurs"] },
      bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] },
      index: 1,
    }),
  );
  assert(lastPage.includes("safe and back home"));
  assert(lastPage.includes("drifted off to sleep"));
});

Deno.test("buildStoryPathSystemPrompt steers away from a branded interest or direction by name", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    brief: { interests: ["Lego", "dinosaurs"], realMoment: null, teach: null, language: "en" },
    input: { kind: "typed", speaker: "kid", text: "put Elsa in it" },
  }));
  assert(prompt.includes("Never use these brand or character names: lego, elsa."));
});

Deno.test("buildStoryPathSystemPrompt adds no brand line when nothing branded came in", () => {
  assertFalse(buildStoryPathSystemPrompt(basePathInput()).includes("Never use these brand or character names"));
});

Deno.test("buildStoryPageSystemPrompt steers away from a branded name in the interests or the planned beat", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    brief: { interests: ["Paw Patrol"], realMoment: null, teach: null, language: "en" },
  }));
  assert(prompt.includes("Never use these brand or character names: paw patrol."));
});

// --- IMP-24 guided setup ---

const kidSara: Kid = { firstName: "Sara", readingLevel: "early_reader", interests: [] };
const plainBrief: StoryBrief = { interests: [], realMoment: null, teach: null, language: "en" };

Deno.test("describeSetup is empty for an old app's brief with nothing set", () => {
  assertEquals(describeSetup(plainBrief, kidSara), []);
});

Deno.test("describeSetup turns hero, place and problem tiles into phrases", () => {
  const lines = describeSetup(
    { ...plainBrief, hero: { tile: "kid" }, place: { tile: "castle" }, problem: { tile: "lost" } },
    kidSara,
  );
  assertEquals(lines, [
    "The hero of this story is Sara, the child this book is for.",
    "The story takes place in a friendly castle.",
    "What goes wrong: something special gets lost.",
  ]);
});

Deno.test("describeSetup quotes a text answer as the family's own words", () => {
  const lines = describeSetup(
    {
      ...plainBrief,
      hero: { text: "a purple owl called Pip", via: "speech" },
      place: { text: "Grandma's\ngarden", via: "typed" },
      problem: { text: "the moon went missing", via: "typed" },
    },
    kidSara,
  ).join("\n");
  assert(lines.includes('The hero of this story, in the family\'s own words: "a purple owl called Pip".'));
  assert(lines.includes('Where the story happens, in the family\'s own words: "Grandma\'s garden".'));
  assert(lines.includes('What goes wrong, in the family\'s own words: "the moon went missing".'));
});

Deno.test("describeSetup ignores an unknown tile and a tile on the wrong card", () => {
  assertEquals(describeSetup({ ...plainBrief, hero: { tile: "hoverboard" }, place: { tile: "dragon" } }, kidSara), []);
});

Deno.test("describeSetup sets the tone for each mood", () => {
  assert(describeSetup({ ...plainBrief, mood: "silly" }, kidSara).join(" ").toLowerCase().includes("silly"));
  assert(describeSetup({ ...plainBrief, mood: "cosy" }, kidSara).join(" ").toLowerCase().includes("cosy"));
  assert(describeSetup({ ...plainBrief, mood: "brave" }, kidSara).join(" ").toLowerCase().includes("brave"));
});

Deno.test("describeSetup asks a bedtime story to end calm and sleepy, and adds nothing for fun", () => {
  assert(describeSetup({ ...plainBrief, purpose: "bedtime" }, kidSara).join(" ").includes("sleepy"));
  assertEquals(describeSetup({ ...plainBrief, purpose: "fun" }, kidSara), []);
});

Deno.test("describeSetup carries the real moment and teach lines", () => {
  const lines = describeSetup({ ...plainBrief, realMoment: "a new baby brother", teach: "sharing" }, kidSara).join("\n");
  assert(lines.includes("a new baby brother"));
  assert(lines.includes("help teach: sharing"));
});

Deno.test("buildStoryPathSystemPrompt: book interests win over the profile when the brief has card answers", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Sara", readingLevel: "early_reader", interests: ["foxes", "stars"] },
    brief: { ...plainBrief, hero: { tile: "dragon" } },
  }));
  assertFalse(prompt.includes("foxes"));
  assertFalse(prompt.includes("Sara loves"));
  assert(prompt.includes("The hero of this story is a small, friendly dragon."));
});

Deno.test("buildStoryPathSystemPrompt: book interests win over the profile when the brief has its own interests", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Sara", readingLevel: "early_reader", interests: ["foxes"] },
    brief: { ...plainBrief, interests: ["trains"] },
  }));
  assert(prompt.includes("Sara loves: trains."));
  assertFalse(prompt.includes("foxes"));
});

Deno.test("buildStoryPathSystemPrompt falls back to the profile's interests for an empty brief", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Sara", readingLevel: "early_reader", interests: ["foxes", "stars"] },
    brief: plainBrief,
  }));
  assert(prompt.includes("Sara loves: foxes, stars."));
});

Deno.test("buildStoryPathSystemPrompt still steers away from a branded profile interest the loves line dropped", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Sara", readingLevel: "early_reader", interests: ["Paw Patrol"] },
    brief: { ...plainBrief, hero: { text: "Elsa", via: "typed" } },
  }));
  assert(prompt.includes("Never use these brand or character names: paw patrol, elsa."));
});

Deno.test("buildStoryPageSystemPrompt now carries the setup, real moment, teach and mood", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    brief: { ...plainBrief, realMoment: "a new baby brother", teach: "sharing", mood: "cosy", hero: { tile: "bunny" } },
  }));
  assert(prompt.includes("a new baby brother"));
  assert(prompt.includes("help teach: sharing"));
  assert(prompt.toLowerCase().includes("cosy"));
  assert(prompt.includes("The hero of this story is a little bunny."));
});

// --- IMP-25 one question per page ---

Deno.test("buildStoryPageSystemPrompt includes the next planned beat so one choice can follow it", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Rex finds the ball under the bed.", "Beat 2"] },
    index: 0,
  }));
  assert(prompt.includes("Rex finds the ball under the bed."));
  assert(prompt.includes('"followsPath": true'));
});

Deno.test("buildStoryPageSystemPrompt asks an early reader for 3 choices about what happens next", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] },
    index: 0,
  }));
  assert(prompt.includes('"kind": "choice"'));
  assert(prompt.includes("exactly 3 choices"));
  assert(prompt.includes("NEXT"));
  assert(prompt.includes("Have you ever"));
  assert(prompt.includes("never about Sara's own address, school or family"));
  assertFalse(prompt.includes("readingQuestion"));
});

Deno.test("buildStoryPageSystemPrompt asks for a talk-only question on a listener page with no choices", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    kid: { firstName: "Sara", readingLevel: "listener", interests: [] },
    bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1", "Beat 2"] },
    index: 0,
  }));
  assert(prompt.includes('"kind": "talkOnly"'));
  assertFalse(prompt.includes("exactly 2 choices"));
});

Deno.test("buildStoryPageSystemPrompt asks for a talk-only question on the ending page", () => {
  const prompt = buildStoryPageSystemPrompt(basePageInput({
    bible: { title: null, setting: "", characters: [], directions: [], path: ["Beat 0", "Beat 1"] },
    index: 1,
  }));
  assert(prompt.includes('"kind": "talkOnly"'));
  assertFalse(prompt.includes('"kind": "choice"'));
});

Deno.test("buildStoryPathSystemPrompt asks a reader for an open question with 3 choices, talk-only if the page ends the path", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Sara", readingLevel: "reader", interests: [] },
  }));
  assert(prompt.includes('"kind": "open"'));
  assert(prompt.includes("exactly 3 choices"));
  assert(prompt.includes("the next beat in the path you return"));
  assert(prompt.includes('If page 0 is the last beat of the path, make it "kind": "talkOnly"'));
});

Deno.test("both prompts' language rule covers the question and choices", () => {
  assert(buildStoryPathSystemPrompt(basePathInput()).includes("question and choices only in English"));
  assert(buildStoryPageSystemPrompt(basePageInput()).includes("question and choices only in English"));
});

Deno.test("buildStoryPathSystemPrompt marks a tapped choice as the child's pick", () => {
  // Mid-story (page 1 is shown): a choice is never the opening idea.
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    index: 1,
    pages: [{ index: 0, text: "The dragon lost his ball." }],
    input: { kind: "choice", speaker: "kid", text: "The dragon looks under the bed." },
  }));
  assert(prompt.includes("The dragon looks under the bed."));
  assert(prompt.includes("picked this from the page's choices"));
});

Deno.test("buildStoryPathSystemPrompt never lists the kid's own name as a brand", () => {
  const prompt = buildStoryPathSystemPrompt(basePathInput({
    kid: { firstName: "Elsa", readingLevel: "early_reader", interests: ["snow"] },
  }));
  assertFalse(prompt.includes("Never use these brand or character names"));
});
