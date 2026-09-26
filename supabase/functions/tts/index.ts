// `tts`: a character's line, for talking characters and video export
// (docs/CONTRACTS.md §3, PRD C4). Requires sign-in and a per-user rate limit.
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { TTS_MODEL } from "../_shared/models.ts";
import { textToSpeechBase64 } from "../_shared/openai_audio.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { requestSchema } from "./schema.ts";

Deno.serve((req) =>
  servePop(req, "tts", async (req) => {
    const { client } = await requireUser(req);
    await enforceStandardRateLimit(client, "tts");

    const { text, voice } = await parseRequest(req, requestSchema);
    const audioBase64 = await textToSpeechBase64(requireEnv("OPENAI_API_KEY"), {
      model: TTS_MODEL,
      voice,
      text,
    });

    return { data: { audioBase64, format: "mp3" } };
  })
);
