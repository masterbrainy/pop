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
