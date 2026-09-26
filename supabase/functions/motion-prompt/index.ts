// `motion-prompt`: the page's animation prompt (docs/CONTRACTS.md §3, PRD P4,
// §8.6 K1). Requires sign-in and a per-user rate limit. The request carries no
// reading level, so the safety gate uses the strictest one ("listener") —
// this is a defense-in-depth check on a page that already passed story-turn's
// own gate, not the app's primary safety mechanism.
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { generateJSON } from "../_shared/gemini_client.ts";
import { servePop } from "../_shared/handler.ts";
import {
  buildMotionPromptInstruction,
  ensureStyleLockedScene,
  MOTION_RESPONSE_SCHEMA,
  motionOutputSchema,
} from "../_shared/motion_prompt.ts";
import { parseModelJSON } from "../_shared/openai_chat.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { PopError } from "../_shared/errors.ts";
import { buildSafetyDeps } from "../_shared/safety_deps.ts";
import { runSafetyGate } from "../_shared/safety.ts";
import { downloadAsBase64 } from "../_shared/storage.ts";
import { requestSchema } from "./schema.ts";

const STRICTEST_READING_LEVEL = "listener";

Deno.serve((req) =>
  servePop(req, "motion-prompt", async (req) => {
    const { client } = await requireUser(req);
    await enforceStandardRateLimit(client, "motion-prompt");

    const body = await parseRequest(req, requestSchema);
    const geminiKey = requireEnv("GEMINI_API_KEY");
    const openaiKey = requireEnv("OPENAI_API_KEY");

    const still = await downloadAsBase64(client, body.stillPath);
    const raw = await generateJSON(geminiKey, {
      instruction: buildMotionPromptInstruction(body.text),
      responseSchema: MOTION_RESPONSE_SCHEMA,
      image: { mimeType: still.mimeType, data: still.base64 },
    });
    const modelOutput = parseModelJSON(raw, motionOutputSchema);
    // Orbis drifted from the watercolor still toward a photoreal look in the
    // 0.3a probe when the scene didn't name the style explicitly, so this is
    // enforced deterministically, not left to the model's compliance alone.
    const scene = ensureStyleLockedScene(modelOutput.scene);

    const verdict = await runSafetyGate(
      [scene, modelOutput.motion],
      STRICTEST_READING_LEVEL,
      buildSafetyDeps(openaiKey),
    );
    if (!verdict.safe) {
      throw new PopError("unsafe", "This page's animation prompt did not pass the safety check.");
    }

    return { data: { scene, motion: modelOutput.motion } };
  })
);
