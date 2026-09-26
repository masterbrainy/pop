// OpenAI text-to-speech (CONTRACTS.md §3 `tts`) and Realtime transcription-only
// client secrets (§3 `stt-token`). The client secret never gets logged.
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { PopError } from "./errors.ts";

const SPEECH_URL = "https://api.openai.com/v1/audio/speech";
const CLIENT_SECRETS_URL = "https://api.openai.com/v1/realtime/client_secrets";

export async function textToSpeechBase64(
  apiKey: string,
  opts: { model: string; voice: string; text: string },
): Promise<string> {
  const res = await fetch(SPEECH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model,
      voice: opts.voice,
      input: opts.text,
      response_format: "mp3",
    }),
  });
  if (!res.ok) {
    throw new PopError("upstream", `Text-to-speech request failed (${res.status})`);
  }
  const bytes = new Uint8Array(await res.arrayBuffer());
  return encodeBase64(bytes);
}

export interface TranscriptionClientSecret {
  clientSecret: string;
  expiresAt: number;
}

/**
 * The exact body the app's Realtime client expects on the other end (checked
 * live against OpenAI's GA `/v1/realtime/client_secrets` endpoint, HTTP 200,
 * on 2026-09-26): the app connects to `wss://api.openai.com/v1/realtime` with
 * `Authorization: Bearer <clientSecret>` (no beta header) and reads
 * `conversation.item.input_audio_transcription.delta`/`.completed`.
 */
export function buildTranscriptionSessionRequestBody(model: string) {
  return {
    expires_after: { anchor: "created_at", seconds: 600 },
    session: {
      type: "transcription",
      audio: {
        input: {
          format: { type: "audio/pcm", rate: 24000 },
          transcription: { model, language: "en" },
          turn_detection: { type: "server_vad", silence_duration_ms: 700 },
          noise_reduction: { type: "near_field" },
        },
      },
    },
  };
}

/**
 * Mints a short-lived client secret for a transcription-only Realtime session
 * with server-side voice activity detection, so the audio goes straight from
 * the app to OpenAI and this key never reaches the client (ROADMAP §3).
 */
export async function createTranscriptionClientSecret(
  apiKey: string,
  model: string,
): Promise<TranscriptionClientSecret> {
  const res = await fetch(CLIENT_SECRETS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(buildTranscriptionSessionRequestBody(model)),
  });
  if (!res.ok) {
    // The response body is OpenAI's own error text, never the key — safe to
    // fold into the message for debugging.
    const detail = await res.text().catch(() => "");
    throw new PopError(
      "upstream",
      `Realtime client secret request failed (${res.status})${detail ? `: ${detail.slice(0, 300)}` : ""}`,
    );
  }
  const body = await res.json() as { value?: string; expires_at?: number };
  if (!body.value || !body.expires_at) {
    throw new PopError("upstream", "Realtime client secret response was missing fields");
  }
  return { clientSecret: body.value, expiresAt: body.expires_at };
}
