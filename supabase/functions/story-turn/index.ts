// `story-turn`: the story path, or a title (P-04, docs/CONTRACTS.md §3, PRD
// S1-S8, S11, S12, S14, §8.6 K1, §8.7). Requires sign-in and a per-user rate
// limit.
//
// `mode: "turn"` (the pre-P-04 append/new_page/revise_current engine) was
// removed once the app moved to `path`/`page` and the full eval passed on
// them (see docs/CONTRACTS.md §3 for the removal note).
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { STORY_MODEL, TITLE_MODEL } from "../_shared/models.ts";
import { chatJSON, parseModelJSON } from "../_shared/openai_chat.ts";
import { moderateText } from "../_shared/openai_moderation.ts";
import { buildInputSafetyDeps, buildSafetyDeps } from "../_shared/safety_deps.ts";
import type { ReadingLevel } from "../_shared/reading_levels.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { buildStoryPageSystemPrompt, buildStoryPathSystemPrompt, buildTitlePrompt } from "../_shared/story_prompt.ts";
import {
  STORY_PAGE_JSON_SCHEMA,
  STORY_PATH_JSON_SCHEMA,
  storyPageModelOutputSchema,
  storyPathModelOutputSchema,
} from "../_shared/story_path_schema.ts";
import { runPageTurn, runPathTurn, type PageModelAttempt, type PathModelAttempt } from "../_shared/story_path.ts";
import { TITLE_JSON_SCHEMA, titleModelOutputSchema } from "../_shared/story_schema.ts";
import { requestSchema, type PageRequest, type PathRequest, type TitleRequest } from "./schema.ts";

const WRITE_NOW = "Produce the JSON response for this turn now.";
const TITLE_SYSTEM_PROMPT =
  "You are Pop!'s story engine, writing a short, warm title for a children's picture book.";
const FALLBACK_TITLE_SUFFIX = "'s Storybook";

async function callPathModelFor(apiKey: string, body: PathRequest, rewriteReason: string | null): Promise<PathModelAttempt> {
  const start = performance.now();
  const raw = await chatJSON(apiKey, {
    model: STORY_MODEL,
    system: buildStoryPathSystemPrompt({ ...body, input: body.input ?? null, rewriteReason }),
    user: WRITE_NOW,
    jsonSchema: STORY_PATH_JSON_SCHEMA,
  });
  const output = parseModelJSON(raw, storyPathModelOutputSchema);
  return { output, modelMs: Math.round(performance.now() - start) };
}

async function handlePath(apiKey: string, body: PathRequest) {
  const readingLevel = body.kid.readingLevel as ReadingLevel;
  return runPathTurn(
    readingLevel,
    body.index,
    body.bible,
    body.kid.firstName,
    body.brief.language,
    body.input ? { text: body.input.text, speaker: body.input.speaker } : null,
    {
      callModel: (rewriteReason) => callPathModelFor(apiKey, body, rewriteReason),
      safety: buildSafetyDeps(apiKey),
      inputSafety: buildInputSafetyDeps(apiKey),
    },
    body.pages.slice().sort((a, b) => a.index - b.index).map((page) => page.text),
  );
}

async function callPageModelFor(apiKey: string, body: PageRequest, rewriteReason: string | null): Promise<PageModelAttempt> {
  const start = performance.now();
  const raw = await chatJSON(apiKey, {
    model: STORY_MODEL,
    system: buildStoryPageSystemPrompt({ ...body, rewriteReason }),
    user: WRITE_NOW,
    jsonSchema: STORY_PAGE_JSON_SCHEMA,
  });
  const output = parseModelJSON(raw, storyPageModelOutputSchema);
  return { output, modelMs: Math.round(performance.now() - start) };
}

async function handlePage(apiKey: string, body: PageRequest) {
  const readingLevel = body.kid.readingLevel as ReadingLevel;
  return runPageTurn(
    readingLevel,
    body.index,
    body.bible,
    body.brief.language,
    {
      callModel: (rewriteReason) => callPageModelFor(apiKey, body, rewriteReason),
      safety: buildSafetyDeps(apiKey),
    },
    body.pages.slice().sort((a, b) => a.index - b.index).map((page) => page.text),
  );
}

async function generateTitle(apiKey: string, body: TitleRequest): Promise<string> {
  const raw = await chatJSON(apiKey, {
    model: TITLE_MODEL,
    system: TITLE_SYSTEM_PROMPT,
    user: buildTitlePrompt(body.bible, body.pages, body.kid.firstName),
    jsonSchema: TITLE_JSON_SCHEMA,
  });
  return parseModelJSON(raw, titleModelOutputSchema).title;
}

async function handleTitle(apiKey: string, body: TitleRequest) {
  let title = await generateTitle(apiKey, body);
  let verdict = await moderateText(apiKey, title);
  if (verdict.flagged) {
    // One safe, deterministic fallback — no second model call needed for a
    // single short title (unlike story-turn's page rewrite).
    title = `${body.kid.firstName}${FALLBACK_TITLE_SUFFIX}`;
    verdict = await moderateText(apiKey, title);
    if (verdict.flagged) title = "A Storybook";
  }
  return { title };
}

type StoryTurnFunctionData =
  | Awaited<ReturnType<typeof handleTitle>>
  | Awaited<ReturnType<typeof handlePath>>
  | Awaited<ReturnType<typeof handlePage>>;

Deno.serve((req) =>
  servePop<StoryTurnFunctionData>(req, "story-turn", async (req) => {
    const { client } = await requireUser(req);
    await enforceStandardRateLimit(client, "story-turn");
    const body = await parseRequest(req, requestSchema);
    const apiKey = requireEnv("OPENAI_API_KEY");

    switch (body.mode) {
      case "title":
        return { data: await handleTitle(apiKey, body) };
      case "path":
        return { data: await handlePath(apiKey, body) };
      case "page":
        return { data: await handlePage(apiKey, body) };
    }
  })
);
