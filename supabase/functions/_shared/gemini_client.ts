// Gemini image generation (`art`) and structured text generation
// (`motion-prompt`). CONTRACTS.md §3 pins the image endpoint, headers and
// generationConfig shape exactly; this wraps both in one small client.
import { PopError } from "./errors.ts";
import { GEMINI_IMAGE_MODEL, GEMINI_TEXT_MODEL } from "./models.ts";
import { fetchWithOneRetry, fetchWithRetry, UPSTREAM_TIMEOUTS_MS } from "./retry.ts";
import { describeGeminiError, geminiErrorCode } from "./gemini_error.ts";

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

export interface InlineImage {
  mimeType: string;
  data: string; // base64
}

interface GeminiPart {
  text?: string;
  inlineData?: { mimeType?: string; data?: string };
}

interface GeminiResponse {
  candidates?: { content?: { parts?: GeminiPart[] } }[];
}

function findImagePart(body: GeminiResponse): GeminiPart | undefined {
  return body.candidates?.[0]?.content?.parts?.find((p) => p.inlineData?.data);
}

function firstText(body: GeminiResponse): string | undefined {
  return body.candidates?.[0]?.content?.parts?.find((p) => p.text)?.text;
}

export interface GenerateImageOptions {
  prompt: string;
  aspectRatio: "16:9" | "2:3" | "1:1";
  referenceImages?: InlineImage[];
}

export interface GeneratedImage {
  base64: string;
  mimeType: string;
}

export async function generateImage(
  apiKey: string,
  opts: GenerateImageOptions,
): Promise<GeneratedImage> {
  const parts: GeminiPart[] = [{ text: opts.prompt }];
  for (const image of opts.referenceImages ?? []) {
    parts.push({ inlineData: { mimeType: image.mimeType, data: image.data } });
  }

  // The image service sometimes turns a burst of calls away (402/429); retry briefly.
  // Each attempt has its own deadline, so one hung call can't hold the page on "Painting…".
  const requestBody = JSON.stringify({
    contents: [{ parts }],
    generationConfig: {
      responseModalities: ["IMAGE"],
      imageConfig: { aspectRatio: opts.aspectRatio },
    },
  });
  const res = await fetchWithRetry((signal) =>
    fetch(`${GEMINI_BASE}/${GEMINI_IMAGE_MODEL}:generateContent`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: requestBody,
      signal,
    }), { timeoutMs: UPSTREAM_TIMEOUTS_MS.geminiImage, label: "Image generation" });
  if (!res.ok) {
    const body = await res.text();
    // The full reason stays in the server log; it can name the Cloud project.
    console.error(`gemini image failed: ${describeGeminiError(res.status, body)}`);
    throw new PopError("upstream", `Image generation failed (${geminiErrorCode(res.status, body)})`);
  }
  const body = await res.json() as GeminiResponse;
  const imagePart = findImagePart(body);
  if (!imagePart?.inlineData?.data) {
    throw new PopError("upstream", "Image generation returned no image");
  }
  return {
    base64: imagePart.inlineData.data,
    mimeType: imagePart.inlineData.mimeType ?? "image/png",
  };
}

export interface GenerateJSONOptions {
  instruction: string;
  responseSchema: unknown;
  image?: InlineImage;
}

/** Returns the raw JSON text; callers parse+validate it against their own zod schema. */
export async function generateJSON(
  apiKey: string,
  opts: GenerateJSONOptions,
): Promise<string> {
  const parts: GeminiPart[] = [{ text: opts.instruction }];
  if (opts.image) {
    parts.push({ inlineData: { mimeType: opts.image.mimeType, data: opts.image.data } });
  }

  const requestBody = JSON.stringify({
    contents: [{ parts }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: opts.responseSchema,
    },
  });
  const res = await fetchWithOneRetry((signal) =>
    fetch(`${GEMINI_BASE}/${GEMINI_TEXT_MODEL}:generateContent`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: requestBody,
      signal,
    }), { timeoutMs: UPSTREAM_TIMEOUTS_MS.geminiText, label: "Gemini text request" });
  if (!res.ok) {
    throw new PopError("upstream", `Gemini text request failed (${res.status})`);
  }
  const body = await res.json() as GeminiResponse;
  const text = firstText(body);
  if (!text) {
    throw new PopError("upstream", "Gemini text request returned no content");
  }
  return text;
}
