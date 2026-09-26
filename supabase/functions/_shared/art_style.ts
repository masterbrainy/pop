// One locked art style for every picture in a book (CONTRACTS.md §3 `art`, PRD P2).

// The leading phrase alone, reused by motion-prompt (0.3a probe finding,
// 2026-09-26): Orbis drifted from the watercolor still toward a photoreal
// look, so every motion-prompt `scene` must start with these exact words too
// — not just the `art` function's images.
export const ART_STYLE_PREFIX = "soft watercolor and colored pencil children's picture-book illustration";

export const ART_STYLE =
  `${ART_STYLE_PREFIX}, ` +
  "warm gentle natural light, gentle rounded friendly shapes, textured paper look, " +
  "a warm muted pastel palette with soft pencil outlines, the same illustrator's hand on every page, " +
  "no text or letters anywhere in the image, no borders or frames, no captions or signatures";

/**
 * Closes every picture prompt, after the scene, so the style is the last thing the image
 * model reads: a page's own words ("a sunny meadow") can otherwise pull the picture toward
 * whatever look they suggest, and a whole book then drifts page by page.
 */
export const ART_STYLE_ENFORCEMENT =
  `Render this strictly as a ${ART_STYLE_PREFIX}, matching the style, palette and line quality of every other page of this book exactly. ` +
  "Never any other medium or look: no photorealism, no photograph, no 3D render, no CGI, no anime, no comic or manga, " +
  "no pixel art, no clip art, no flat vector, no oil painting, no sketch-only. Keep every character's proportions and colours as in its reference.";

/**
 * Words the story model sometimes puts in an art prompt that name a medium, camera or
 * rendering look. They fight the locked style, so they're cut before the prompt is sent.
 */
const STYLE_DRIFT_TERMS = [
  "photorealistic", "photo-realistic", "photoreal", "photograph", "photographic", "realistic", "hyperrealistic", "hyper-realistic",
  "3d render", "3d rendered", "3d", "cgi", "unreal engine", "octane", "ray-traced", "raytraced", "rendered",
  "anime", "manga", "comic book", "comic-book", "cartoon", "pixel art", "pixel-art", "clip art", "clipart", "vector", "flat design",
  "oil painting", "acrylic", "digital painting", "digital art", "concept art", "line art", "sketch", "pencil sketch", "charcoal",
  "cinematic", "dslr", "bokeh", "8k", "4k", "hdr", "high detail", "highly detailed", "ultra detailed", "trending on artstation",
  "in the style of", "style of",
];

const STYLE_DRIFT_PATTERN = new RegExp(
  `(?:,\\s*)?\\b(?:${STYLE_DRIFT_TERMS.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\s+/g, "\\s+")).join("|")})\\b`,
  "giu",
);

/** True when `prompt` names a medium, camera or rendering look of its own. */
export function namesAnotherStyle(prompt: string): boolean {
  STYLE_DRIFT_PATTERN.lastIndex = 0;
  return STYLE_DRIFT_PATTERN.test(prompt);
}

/** `prompt` with any medium, camera or rendering words removed, whitespace and commas tidied. */
export function withoutStyleDrift(prompt: string): string {
  return prompt
    .replace(STYLE_DRIFT_PATTERN, "")
    .replace(/\s{2,}/g, " ")
    .replace(/\s+([,.;])/g, "$1")
    .replace(/,\s*,/g, ",")
    .replace(/^[\s,]+|[\s,]+$/g, "")
    .trim();
}

/** Characters rarely use this colour, so the device can cut them out cleanly. */
export const CUTOUT_BACKDROP_HEX = "#FF00FF";

export const CUTOUT_BACKGROUND_INSTRUCTION =
  `a single character, centered, full body visible, with a clear dark outline, on a completely flat, untextured, solid magenta background (${CUTOUT_BACKDROP_HEX}) ` +
  "that reaches every edge of the picture; no paper texture, no ground, no plants, no sparkles, no props other than what the character holds, no shadow on the background";

export const PLATE_INSTRUCTION =
  "the same scene and setting with no characters present, as if they had stepped out of frame; " +
  "keep the background, props and lighting identical to the page illustration";

/** `drawing` kind (Phase 8 "kid's drawing as the hero"): redraws a kid's own
 * finger drawing into a character reference image. Reuses the exact cutout
 * backdrop treatment so the result is interchangeable with a `cutout` picture. */
export const DRAWING_INSTRUCTION =
  "The attached image is a child's own drawing. Redraw it as " +
  CUTOUT_BACKGROUND_INSTRUCTION +
  "; keep the drawing's shapes, colours and distinguishing features recognisable as the same character.";

export type ArtKind = "page" | "cover" | "character" | "plate" | "cutout" | "drawing";

/** Aspect ratio per CONTRACTS.md §3: page/plate/cutout 16:9, cover 2:3, character 1:1. */
export function aspectRatioFor(kind: ArtKind): "16:9" | "2:3" | "1:1" {
  switch (kind) {
    case "cover":
      return "2:3";
    case "character":
      return "1:1";
    default:
      return "16:9";
  }
}
