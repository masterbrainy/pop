// Model choices, pinned after checking what each key can actually use
// (see the deploy report for the OpenAI GET /v1/models check on 2026-09-25).

// Story engine: creative structured-output writing at low latency.
export const STORY_MODEL = "gpt-5.4-mini";
// Kid-safety rubric verdict: a small classification-shaped JSON call, so the
// fastest tier is enough and keeps the safety gate from dominating latency.
export const RUBRIC_MODEL = "gpt-5.4-nano";
// Title generation reuses the story model (same creative-writing needs).
export const TITLE_MODEL = STORY_MODEL;

export const MODERATION_MODEL = "omni-moderation-latest";
export const TTS_MODEL = "gpt-4o-mini-tts";
// Matches the exact model id OpenAI's own realtime transcription-session
// example uses, and it's in this key's model list.
export const TRANSCRIBE_MODEL = "gpt-transcribe";

export const GEMINI_IMAGE_MODEL = "gemini-2.5-flash-image";
export const GEMINI_TEXT_MODEL = "gemini-2.5-flash";

export const REACTOR_MODEL = "reactor/visko-orbis-stable";
