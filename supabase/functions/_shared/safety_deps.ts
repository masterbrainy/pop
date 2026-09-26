// The real (network-backed) SafetyDeps used by both story-turn and
// motion-prompt: OpenAI moderation plus the fast LLM rubric-verdict check
// (PRD §8.6 K1). Kept as one shared wiring function so both functions build
// their safety gate identically (DRY) — the orchestration itself (safety.ts,
// story_turn.ts) stays pure and network-free for testing.
import { RUBRIC_MODEL } from "./models.ts";
import { chatJSON, parseModelJSON } from "./openai_chat.ts";
import { moderateText } from "./openai_moderation.ts";
import { describeReadingLevelForPrompt } from "./reading_levels.ts";
import { directionSafetyCheckPrompt, realHarmCheckPrompt, rubricCheckPrompt } from "./safety_rubric.ts";
import type { SafetyDeps } from "./safety.ts";
import type { InputSafetyDeps } from "./input_safety.ts";
import { RUBRIC_JSON_SCHEMA, rubricModelOutputSchema } from "./story_schema.ts";

export function buildSafetyDeps(openaiApiKey: string): SafetyDeps {
  return {
    moderateText: (text) => moderateText(openaiApiKey, text),
    checkRubric: async (combinedText, level) => {
      const raw = await chatJSON(openaiApiKey, {
        model: RUBRIC_MODEL,
        system: rubricCheckPrompt(describeReadingLevelForPrompt(level)),
        user: combinedText,
        jsonSchema: RUBRIC_JSON_SCHEMA,
      });
      return parseModelJSON(raw, rubricModelOutputSchema);
    },
  };
}

/** The real (network-backed) InputSafetyDeps (R-37/R-41): moderation, the fast real-harm rubric check, and the parent direction-safety second opinion. */
export function buildInputSafetyDeps(openaiApiKey: string): InputSafetyDeps {
  return {
    moderateText: (text) => moderateText(openaiApiKey, text),
    checkRealHarm: async (text) => {
      const raw = await chatJSON(openaiApiKey, {
        model: RUBRIC_MODEL,
        system: realHarmCheckPrompt(),
        user: text,
        jsonSchema: RUBRIC_JSON_SCHEMA,
      });
      return parseModelJSON(raw, rubricModelOutputSchema);
    },
    checkDirectionSafety: async (text) => {
      const raw = await chatJSON(openaiApiKey, {
        model: RUBRIC_MODEL,
        system: directionSafetyCheckPrompt(),
        user: text,
        jsonSchema: RUBRIC_JSON_SCHEMA,
      });
      return parseModelJSON(raw, rubricModelOutputSchema);
    },
  };
}
