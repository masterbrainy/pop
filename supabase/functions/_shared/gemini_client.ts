// Gemini image generation for `art` (every picture kind). CONTRACTS.md §3 pins
// the endpoint, headers and generationConfig shape. motion-prompt uses OpenAI.
import { PopError } from "./errors.ts";
import { GEMINI_IMAGE_MODEL } from "./models.ts";
import { fetchWithRetry, UPSTREAM_TIMEOUTS_MS } from "./retry.ts";
import { describeGeminiError, geminiErrorCode } from "./gemini_error.ts";

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const IMAGE_RETRY_DELAYS_MS = [2_000];

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

  // The image service sometimes turns a burst of calls away (402/429); retry once after
  // 2 s. Each attempt has its own deadline, so one picture stays well under the app's
  // wait and Supabase's limit (R-49).
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
    }), { delaysMs: IMAGE_RETRY_DELAYS_MS, timeoutMs: UPSTREAM_TIMEOUTS_MS.image, label: "Image generation" });
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
