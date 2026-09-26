// `moderate`: ad-hoc safety check, used by the app as a frame tripwire
// (docs/CONTRACTS.md §3, PRD P4). Requires sign-in and a per-user rate limit.
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { moderateImageDataUrl, moderateText } from "../_shared/openai_moderation.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { requestSchema } from "./schema.ts";

Deno.serve((req) =>
  servePop(req, "moderate", async (req) => {
    const { client } = await requireUser(req);
    await enforceStandardRateLimit(client, "moderate");

    const body = await parseRequest(req, requestSchema);
    const apiKey = requireEnv("OPENAI_API_KEY");

    // requestSchema is a union of exactly these two shapes, so this is exhaustive.
    const result = "text" in body
      ? await moderateText(apiKey, body.text)
      : await moderateImageDataUrl(apiKey, `data:${body.mimeType};base64,${body.imageBase64}`);

    return { data: result };
  })
);
