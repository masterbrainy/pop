// OpenAI omni-moderation-latest wrapper (PRD §8.6 K1). Parsing is a pure
// function so it's tested against a recorded fixture, with no network call.
import { MODERATION_MODEL } from "./models.ts";
import { PopError } from "./errors.ts";
import type { ModerationResult } from "./safety.ts";

const MODERATION_URL = "https://api.openai.com/v1/moderations";

interface RawModerationResponse {
  results?: { flagged?: boolean; categories?: Record<string, boolean> }[];
}

export function parseModerationResponse(body: RawModerationResponse): ModerationResult {
  const result = body.results?.[0];
  if (!result) {
    return { flagged: false, categories: [] };
  }
  const categories = Object.entries(result.categories ?? {})
    .filter(([, flagged]) => flagged)
    .map(([name]) => name);
  return { flagged: result.flagged === true, categories };
}

async function callModeration(apiKey: string, input: unknown): Promise<ModerationResult> {
  const res = await fetch(MODERATION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model: MODERATION_MODEL, input }),
  });
  if (!res.ok) {
    throw new PopError("upstream", `Moderation request failed (${res.status})`);
  }
  const body = await res.json() as RawModerationResponse;
  return parseModerationResponse(body);
}

export function moderateText(apiKey: string, text: string): Promise<ModerationResult> {
  return callModeration(apiKey, text);
}

/** `dataUrl` is a full `data:<mime>;base64,<...>` string. */
export function moderateImageDataUrl(
  apiKey: string,
  dataUrl: string,
): Promise<ModerationResult> {
  return callModeration(apiKey, [{ type: "image_url", image_url: { url: dataUrl } }]);
}
