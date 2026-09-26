// `art`: one picture (docs/CONTRACTS.md §3 `art`, PRD S6, P2, pop-up layers,
// cover). Requires sign-in, a per-user per-minute rate limit and a per-user
// daily cap (ART_DAILY_LIMIT — image generation is the priciest call here).
import { decodeBase64 } from "jsr:@std/encoding@1/base64";
import { aspectRatioFor } from "../_shared/art_style.ts";
import {
  buildArtPrompt,
  drawingInlineImage,
  referencePathsFor,
  SAFER_REGENERATION_SUFFIX,
  STANDARD_DIMENSIONS,
} from "../_shared/art_request.ts";
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { generateImage, type InlineImage } from "../_shared/gemini_client.ts";
import { moderateImageDataUrl, moderateText } from "../_shared/openai_moderation.ts";
import { pngDimensions } from "../_shared/png.ts";
import { ART_DAILY_LIMIT, DAY_SECONDS, enforceRateLimit, enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { artObjectPath, createSignedUrl, downloadAsBase64, uploadPng } from "../_shared/storage.ts";
import { requestSchema, type ArtRequest } from "./schema.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";

interface ArtResponseData {
  path: string;
  url: string;
  width: number;
  height: number;
  placeholder: boolean;
  ms: number;
}

async function loadReferenceImages(
  client: SupabaseClient,
  body: ArtRequest,
): Promise<InlineImage[]> {
  const paths = referencePathsFor(body.kind, body.characters, body.characterId);
  const images: InlineImage[] = [];
  for (const path of paths) {
    const { base64, mimeType } = await downloadAsBase64(client, path);
    images.push({ data: base64, mimeType });
  }
  return images;
}

/** For `kind: "drawing"`: moderates the kid's drawing and description before
 * any Gemini call, so unsafe input never reaches image generation. */
async function drawingInputFlagged(
  openaiKey: string,
  drawing: InlineImage,
  prompt: string,
): Promise<boolean> {
  const [imageVerdict, textVerdict] = await Promise.all([
    moderateImageDataUrl(openaiKey, `data:${drawing.mimeType};base64,${drawing.data}`),
    moderateText(openaiKey, prompt),
  ]);
  return imageVerdict.flagged || textVerdict.flagged;
}

Deno.serve((req) =>
  servePop<ArtResponseData>(req, "art", async (req) => {
    const { client, userId } = await requireUser(req);
    await enforceStandardRateLimit(client, "art");
    await enforceRateLimit(client, "art-daily", ART_DAILY_LIMIT, DAY_SECONDS);

    const body = await parseRequest(req, requestSchema);
    const geminiKey = requireEnv("GEMINI_API_KEY");
    const openaiKey = requireEnv("OPENAI_API_KEY");
    const aspectRatio = aspectRatioFor(body.kind);
    const start = performance.now();

    const drawing = drawingInlineImage(body.kind, body.drawing);
    if (drawing && await drawingInputFlagged(openaiKey, drawing, body.prompt)) {
      const { width, height } = STANDARD_DIMENSIONS[aspectRatio];
      return {
        data: { path: "", url: "", width, height, placeholder: true, ms: Math.round(performance.now() - start) },
      };
    }

    const referenceImages = await loadReferenceImages(client, body);
    if (drawing) referenceImages.push(drawing);
    const prompt = buildArtPrompt(body.kind, body.prompt, body.characters, body.characterId);

    let generated = await generateImage(geminiKey, { prompt, aspectRatio, referenceImages });
    let verdict = await moderateImageDataUrl(
      openaiKey,
      `data:${generated.mimeType};base64,${generated.base64}`,
    );

    if (verdict.flagged) {
      generated = await generateImage(geminiKey, {
        prompt: `${prompt}\n\n${SAFER_REGENERATION_SUFFIX}`,
        aspectRatio,
        referenceImages,
      });
      verdict = await moderateImageDataUrl(
        openaiKey,
        `data:${generated.mimeType};base64,${generated.base64}`,
      );
    }

    const ms = Math.round(performance.now() - start);

    if (verdict.flagged) {
      const { width, height } = STANDARD_DIMENSIONS[aspectRatio];
      return { data: { path: "", url: "", width, height, placeholder: true, ms } };
    }

    const bytes = decodeBase64(generated.base64);
    const { width, height } = pngDimensions(bytes);
    const path = artObjectPath({
      userId,
      bookId: body.bookId,
      kind: body.kind,
      version: body.version,
      pageIndex: body.pageIndex ?? undefined,
      characterId: body.characterId ?? undefined,
    });
    await uploadPng(client, path, bytes);
    const url = await createSignedUrl(client, path);

    return { data: { path, url, width, height, placeholder: false, ms } };
  })
);
