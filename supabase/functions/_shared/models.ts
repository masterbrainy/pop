// Model choices, pinned after checking what each key can actually use
// (see the deploy report for the OpenAI GET /v1/models check on 2026-09-26).

// Story engine: creative structured-output writing at low latency.
export const STORY_MODEL = "gpt-5.4-mini";
// Kid-safety rubric verdict: a small classification-shaped JSON call, so the
// fastest tier is enough and keeps the safety gate from dominating latency.
export const RUBRIC_MODEL = "gpt-5.4-nano";
// Title generation reuses the story model (same creative-writing needs).
export const TITLE_MODEL = STORY_MODEL;

export const MODERATION_MODEL = "omni-moderation-latest";
export const TTS_MODEL = "gpt-4o-mini-tts";
// Matches the app's Realtime client (ROADMAP §2): checked live against the GA
// /v1/realtime/client_secrets endpoint on 2026-09-26 (HTTP 200), and it's in
// this key's model list.
export const TRANSCRIBE_MODEL = "gpt-4o-transcribe";

// P-05 (accepted 2026-09-26): OpenAI paints every picture; measured 12-13 s for a
// 1536x1024 page at medium quality, about $0.011 each (docs/PIVOTS.md P-05).
export const IMAGE_MODEL = "gpt-image-2.5-flare";
export const IMAGE_QUALITY = "medium";
// motion-prompt reads the page's still and text with the story model.
export const MOTION_MODEL = STORY_MODEL;

export const REACTOR_MODEL = "reactor/visko-orbis-stable";
