// PRD §8.6 kid-safety rubric, condensed for prompts. Keep this in sync with
// docs/PRD.md §8.6 if the rubric table changes; the builder owns that file.

export const KID_SAFETY_RUBRIC = `Kid-safety rubric. Reject or soften anything in these categories:
- Violence and injury: no hitting that hurts, no blood, no weapons used on someone. A tumble or a bumped knee that gets better is fine.
- Too scary for the age: no monsters that chase or threaten, no menacing dark for young children. A friendly dragon, or mild suspense that resolves on the same page, is fine for older children.
- Peril and separation: no child lost or left alone, no parent hurt or gone. A short search for a lost toy that ends happily is fine.
- Meanness: no bullying, name-calling, or cruelty that wins. Someone being unkind and then apologizing and making up is fine.
- Adult themes: no romance, detailed death, drugs, alcohol, gambling, or crime.
- Danger a child could copy: no playing with fire, knives, medicine, or cleaning products; no deep water alone; no going off with a stranger. A grown-up helping, with the safe choice shown as right, is fine.
- Real people and brands: no public figures, other real people by full name, logos, or branded characters. Invented characters only.
- Personal details: no surnames, addresses, schools, or phone numbers. The kid's first name alone is fine.
A real moment the parent asked for (a new sibling, a move, a loss) is allowed if it is told gently, with a reassuring ending.`;

/** The prompt for the fast LLM rubric-verdict check, run alongside moderation. */
export function rubricCheckPrompt(readingLevelDescription: string): string {
  return `You are a strict but kind children's-book safety reviewer.
The reader is a child at this level: ${readingLevelDescription}

${KID_SAFETY_RUBRIC}

Read the CONTENT the user provides and reply with only a JSON object:
{"safe": boolean, "reason": string}
"reason" must be empty when safe is true, and a short (under 20 words) plain-English reason when safe is false.`;
}

/**
 * The prompt for the input-side real-harm check (R-37, PRD §8.6): a cheap,
 * fast classification of a kid's own turn input, run before it ever reaches
 * the story engine. Separate from `rubricCheckPrompt` because it judges the
 * child's real-life words, not the model's story output.
 */
export function realHarmCheckPrompt(): string {
  return `You check a child's own words, said while making a picture book with a parent, for signs of real harm happening to them in real life — for example abuse, being hurt by someone, neglect, or a real danger they're describing about themselves or their home, not something they're imagining for the story.
Ordinary play, made-up story ideas, silly or scary-sounding pretend, and unrelated chatter are all safe.

Read the CHILD'S WORDS and reply with only a JSON object:
{"safe": boolean, "reason": string}
"safe" is false only when the words sound like the child may be describing real harm to themselves; true otherwise.
"reason" must be empty when safe is true, and a short (under 20 words) plain-English reason when safe is false.`;
}

/**
 * The prompt for the input-side direction-safety second opinion (R-41
 * root-cause fix, docs/CONTRACTS.md): OpenAI's moderation model can flag an
 * ordinary, benign parent direction as a false positive — observed live, it
 * flagged "Let's finish the story here with a proper ending." under its
 * "violence" category. A parent is the trusted adult steering the story
 * (PRD "Parents drive creation"), so a moderation flag on their words gets
 * this fast second opinion before blocking; a kid's own words never get this
 * override (see realHarmCheckPrompt/checkRealHarm, always run and never
 * overturned for a kid speaker).
 */
export function directionSafetyCheckPrompt(): string {
  return `You check a parent's own instruction to a children's picture-book story engine for a genuine safety concern.
Content moderation can over-trigger on ordinary, benign instructions — for example ending the story, asking for a happy or exciting moment, or a plain scene change — treat those as safe.
Judge it for the youngest reader Pop! serves, a child as young as 3, against this rubric:
${KID_SAFETY_RUBRIC}

Read the PARENT'S INSTRUCTION and reply with only a JSON object:
{"safe": boolean, "reason": string}
"safe" is false only when the instruction itself asks for something genuinely unsafe for a children's story (real violence, adult themes, danger a child could copy, real people, personal details, and similar); true otherwise, including any ordinary instruction a blunt filter might misflag.
"reason" must be empty when safe is true, and a short (under 20 words) plain-English reason when safe is false.`;
}
