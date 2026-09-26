// OpenAI image generation for `art` (P-05, accepted 2026-09-26: OpenAI replaces
// Gemini). A picture with reference images (characters, a kid's drawing) goes
// through the edits endpoint so the references steer it; otherwise generations.
// OpenAI has no 16:9 size, so pages come back 1536×1024 (3:2) and the app
// crops to 16:9 when it shows or animates them.
import { decodeBase64 } from "jsr:@std/encoding@1/base64";
import { PopError } from "./errors.ts";
import { IMAGE_MODEL, IMAGE_QUALITY } from "./models.ts";
import { fetchWithOneRetry, UPSTREAM_TIMEOUTS_MS } from "./retry.ts";

const GENERATIONS_URL = "https://api.openai.com/v1/images/generations";
const EDITS_URL = "https://api.openai.com/v1/images/edits";

export interface InlineImage {
  mimeType: string;
  data: string; // base64
}

export type AspectRatio = "16:9" | "2:3" | "1:1";

export interface GenerateImageOptions {
  prompt: string;
  aspectRatio: AspectRatio;
  referenceImages?: InlineImage[];
}

export interface GeneratedImage {
  base64: string;
  mimeType: string;
}

/** OpenAI's own safety system refused the prompt; `art` shows the placeholder. */
export class ImageBlockedError extends Error {
  constructor() {
    super("Image generation was blocked by the provider's safety system");
  }
}

/** The nearest OpenAI size to each aspect ratio in CONTRACTS.md §3. */
export function openAISizeFor(aspectRatio: AspectRatio): string {
  switch (aspectRatio) {
    case "16:9":
      return "1536x1024";
    case "2:3":
      return "1024x1536";
    case "1:1":
      return "1024x1024";
  }
}

function extensionFor(mimeType: string): string {
  return mimeType === "image/jpeg" ? "jpg" : "png";
}

function editsBody(opts: GenerateImageOptions, references: InlineImage[]): FormData {
  const form = new FormData();
  form.append("model", IMAGE_MODEL);
  form.append("prompt", opts.prompt);
  form.append("size", openAISizeFor(opts.aspectRatio));
  form.append("quality", IMAGE_QUALITY);
  form.append("n", "1");
  references.forEach((image, i) => {
    const blob = new Blob([decodeBase64(image.data)], { type: image.mimeType });
    form.append("image[]", blob, `reference-${i}.${extensionFor(image.mimeType)}`);
  });
  return form;
}

function generationsBody(opts: GenerateImageOptions): string {
  return JSON.stringify({
    model: IMAGE_MODEL,
    prompt: opts.prompt,
    size: openAISizeFor(opts.aspectRatio),
    quality: IMAGE_QUALITY,
    n: 1,
  });
}

function isModerationBlock(status: number, body: string): boolean {
  return status === 400 && body.includes("moderation_blocked");
}

export async function generateImage(apiKey: string, opts: GenerateImageOptions): Promise<GeneratedImage> {
  const references = opts.referenceImages ?? [];
  const useEdits = references.length > 0;
  // One deadline-bound attempt plus one quick retry on 429/5xx, so a picture can't
  // outlast the app's art wait or Supabase's request limit (R-49).
  const res = await fetchWithOneRetry((signal) =>
    fetch(useEdits ? EDITS_URL : GENERATIONS_URL, {
      method: "POST",
      headers: useEdits
        ? { Authorization: `Bearer ${apiKey}` }
        : { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      // A FormData body can only be read once, so each attempt builds its own.
      body: useEdits ? editsBody(opts, references) : generationsBody(opts),
      signal,
    }), { timeoutMs: UPSTREAM_TIMEOUTS_MS.image, label: "Image generation" });
  if (!res.ok) {
    const body = await res.text();
    if (isModerationBlock(res.status, body)) throw new ImageBlockedError();
    console.error(`openai image failed: HTTP ${res.status} ${body.slice(0, 300)}`);
    throw new PopError("upstream", `Image generation failed (${res.status})`);
  }
  const reply = await res.json() as { data?: { b64_json?: string }[] };
  const base64 = reply.data?.[0]?.b64_json;
  if (!base64) throw new PopError("upstream", "Image generation returned no image");
  return { base64, mimeType: "image/png" };
}
