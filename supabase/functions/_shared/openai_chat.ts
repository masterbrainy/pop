// OpenAI Chat Completions with strict JSON-schema structured output, used by
// story-turn's engine call, its safety-rubric check, and title generation.
import { PopError } from "./errors.ts";

const CHAT_URL = "https://api.openai.com/v1/chat/completions";

export interface JsonSchemaSpec {
  name: string;
  strict: boolean;
  schema: unknown;
}

export interface ChatJSONOptions {
  model: string;
  system: string;
  user: string;
  jsonSchema: JsonSchemaSpec;
}

interface RawChatResponse {
  choices?: { message?: { content?: string } }[];
}

/** Returns the raw JSON string the model produced; callers parse+validate it. */
export async function chatJSON(apiKey: string, opts: ChatJSONOptions): Promise<string> {
  const res = await fetch(CHAT_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      messages: [
        { role: "system", content: opts.system },
        { role: "user", content: opts.user },
      ],
      response_format: { type: "json_schema", json_schema: opts.jsonSchema },
    }),
  });
  if (!res.ok) {
    throw new PopError("upstream", `Model request failed (${res.status})`);
  }
  const body = await res.json() as RawChatResponse;
  const content = body.choices?.[0]?.message?.content;
  if (!content) {
    throw new PopError("upstream", "Model returned no content");
  }
  return content;
}

/** Parses and validates a model's raw JSON string against a zod schema. */
export function parseModelJSON<T>(raw: string, schema: { parse: (v: unknown) => T }): T {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new PopError("upstream", "Model returned invalid JSON");
  }
  try {
    return schema.parse(parsed);
  } catch {
    throw new PopError("upstream", "Model response did not match the expected shape");
  }
}
