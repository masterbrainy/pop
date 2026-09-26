import { assertEquals } from "jsr:@std/assert@1";
import { buildTranscriptionSessionRequestBody } from "./openai_audio.ts";

Deno.test("buildTranscriptionSessionRequestBody matches the GA client_secrets contract exactly", () => {
  assertEquals(buildTranscriptionSessionRequestBody("gpt-4o-transcribe"), {
    expires_after: { anchor: "created_at", seconds: 600 },
    session: {
      type: "transcription",
      audio: {
        input: {
          format: { type: "audio/pcm", rate: 24000 },
          transcription: { model: "gpt-4o-transcribe", language: "en" },
          turn_detection: { type: "server_vad", silence_duration_ms: 700 },
          noise_reduction: { type: "near_field" },
        },
      },
    },
  });
});

Deno.test("buildTranscriptionSessionRequestBody uses whatever model it's given", () => {
  const body = buildTranscriptionSessionRequestBody("some-other-model");
  assertEquals(body.session.audio.input.transcription.model, "some-other-model");
});
