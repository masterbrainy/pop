// The `motion-prompt` function's own Gemini prompt: read this page's still and
// text, describe only what's already there (CONTRACTS.md §3 `motion-prompt`).
// Distinct from PopKit's MotionPromptBuilder, which assembles the app-side
// Orbis prompt from this function's {scene, motion} output.
import { z } from "npm:zod@3.23.8";

export function buildMotionPromptInstruction(pageText: string): string {
  return [
    `This page's text: "${pageText}"`,
    "Look only at the attached picture and this text. Do not invent anything that isn't already visible or stated.",
    'Respond with only JSON: {"scene": string, "motion": string}.',
    '"scene": one or two plain sentences describing what is visibly in this picture (setting, characters, mood).',
    '"motion": ONE gentle motion clause using only things already in the scene (for example, "the leaves sway softly"). ' +
      "Nothing new may enter the scene. Keep it calm, continuous, and suitable for a young child.",
  ].join("\n");
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
