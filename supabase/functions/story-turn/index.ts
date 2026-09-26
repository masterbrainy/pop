// `story-turn`: one story engine turn, or a title (docs/CONTRACTS.md §3, PRD
// S1-S8, S11, §8.6 K1, §8.7). Requires sign-in and a per-user rate limit.
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { STORY_MODEL, TITLE_MODEL } from "../_shared/models.ts";
import { chatJSON, parseModelJSON } from "../_shared/openai_chat.ts";
import { moderateText } from "../_shared/openai_moderation.ts";
import { buildSafetyDeps } from "../_shared/safety_deps.ts";
import type { ReadingLevel } from "../_shared/reading_levels.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { buildStoryTurnSystemPrompt, buildTitlePrompt } from "../_shared/story_prompt.ts";
import {
  STORY_TURN_JSON_SCHEMA,
  storyModelOutputSchema,
  TITLE_JSON_SCHEMA,
  titleModelOutputSchema,
} from "../_shared/story_schema.ts";
import { runStoryTurn, type ModelAttempt } from "../_shared/story_turn.ts";
import { requestSchema, type TitleRequest, type TurnRequest } from "./schema.ts";

const WRITE_NOW = "Produce the JSON response for this turn now.";
const TITLE_SYSTEM_PROMPT =
  "You are Pop!'s story engine, writing a short, warm title for a children's picture book.";
const FALLBACK_TITLE_SUFFIX = "'s Storybook";

async function callModelFor(apiKey: string, body: TurnRequest, rewriteReason: string | null): Promise<ModelAttempt> {
  const start = performance.now();
  const raw = await chatJSON(apiKey, {
    model: STORY_MODEL,
    system: buildStoryTurnSystemPrompt({ ...body, rewriteReason }),
    user: WRITE_NOW,
    jsonSchema: STORY_TURN_JSON_SCHEMA,
  });
  const output = parseModelJSON(raw, storyModelOutputSchema);
  return { output, modelMs: Math.round(performance.now() - start) };
}

async function handleTurn(apiKey: string, body: TurnRequest) {
  const readingLevel = body.kid.readingLevel as ReadingLevel;
  const data = await runStoryTurn(
    readingLevel,
    body.current.index,
    body.current.text,
    body.bible,
    {
      callModel: (rewriteReason) => callModelFor(apiKey, body, rewriteReason),
      safety: buildSafetyDeps(apiKey),
    },
  );
  return data;
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

Deno.serve((req) =>
  servePop(req, "story-turn", async (req) => {
    const { client } = await requireUser(req);
    await enforceStandardRateLimit(client, "story-turn");
    const body = await parseRequest(req, requestSchema);
    const apiKey = requireEnv("OPENAI_API_KEY");

    const data = body.mode === "turn" ? await handleTurn(apiKey, body) : await handleTitle(apiKey, body);
    return { data };
  })
);
