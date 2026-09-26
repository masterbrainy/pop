// `stt-token`: a short-lived OpenAI Realtime transcription-only client secret
// (docs/CONTRACTS.md §3, PRD S1). Audio goes straight from the app to OpenAI
// and is never stored server-side; this function never logs the secret.
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { TRANSCRIBE_MODEL } from "../_shared/models.ts";
import { createTranscriptionClientSecret } from "../_shared/openai_audio.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { requestSchema } from "./schema.ts";

Deno.serve((req) =>
  servePop(req, "stt-token", async (req) => {
    const { client } = await requireUser(req);
    await enforceStandardRateLimit(client, "stt-token");
    await parseRequest(req, requestSchema);

    const secret = await createTranscriptionClientSecret(
      requireEnv("OPENAI_API_KEY"),
      TRANSCRIBE_MODEL,
    );

    return {
      data: {
        clientSecret: secret.clientSecret,
        expiresAt: secret.expiresAt,
        model: TRANSCRIBE_MODEL,
      },
    };
  })
);
