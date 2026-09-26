// The `motion-prompt` function's own Gemini prompt: read this page's still and
// text, describe only what's already there (CONTRACTS.md §3 `motion-prompt`).
// Distinct from PopKit's MotionPromptBuilder, which assembles the app-side
// Orbis prompt from this function's {scene, motion} output.
//
// 0.3a probe finding (2026-09-26): Orbis drifted from the watercolor still
// toward a photoreal look, so `scene` must start with the same locked style
// words as the `art` function's images — asked for in the prompt below, and
// enforced deterministically by `ensureStyleLockedScene` regardless of
// whether the model actually complies.
import { z } from "npm:zod@3.23.8";
import { ART_STYLE_PREFIX } from "./art_style.ts";

export function buildMotionPromptInstruction(pageText: string): string {
  return [
    `This page's text: "${pageText}"`,
    "Look only at the attached picture and this text. Do not invent anything that isn't already visible or stated.",
    'Respond with only JSON: {"scene": string, "motion": string}.',
    `"scene": start with exactly this phrase: "${ART_STYLE_PREFIX}", then continue with one or two plain sentences describing what is visibly in this picture (setting, characters, mood). For example: "${ART_STYLE_PREFIX} of a dinosaur in a sunny meadow."`,
    '"motion": ONE gentle motion clause using only things already in the scene (for example, "the leaves sway softly"). ' +
      "Nothing new may enter the scene. Keep it calm, continuous, and suitable for a young child. " +
      "Never name a camera move, a medium or a visual style in either field; the picture-book look is fixed.",
  ].join("\n");
}

/**
 * Guarantees `scene` starts with the locked art style regardless of whether
 * the model actually followed the prompt above (Orbis drifts toward
 * photoreal without it) — a deterministic fallback, not a substitute for the
 * prompt instruction.
 */
export function ensureStyleLockedScene(scene: string): string {
  const trimmed = scene.trim();
  if (trimmed.toLowerCase().startsWith(ART_STYLE_PREFIX.toLowerCase())) {
    return trimmed;
  }
  if (trimmed.length === 0) return ART_STYLE_PREFIX;
  const rest = trimmed.charAt(0).toLowerCase() + trimmed.slice(1);
  return `${ART_STYLE_PREFIX} of ${rest}`;
}

export const MOTION_RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    scene: { type: "string" },
    motion: { type: "string" },
  },
  required: ["scene", "motion"],
} as const;

export const motionOutputSchema = z.object({
  scene: z.string(),
  motion: z.string(),
});

export type MotionOutput = z.infer<typeof motionOutputSchema>;
