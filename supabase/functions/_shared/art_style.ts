// One locked art style for every picture in a book (CONTRACTS.md §3 `art`, PRD P2).

// The leading phrase alone, reused by motion-prompt (0.3a probe finding,
// 2026-09-26): Orbis drifted from the watercolor still toward a photoreal
// look, so every motion-prompt `scene` must start with these exact words too
// — not just the `art` function's images.
export const ART_STYLE_PREFIX = "soft watercolor and colored pencil children's picture-book illustration";

export const ART_STYLE =
  `${ART_STYLE_PREFIX}, ` +
  "warm gentle natural light, gentle rounded friendly shapes, textured paper look, " +
  "no text or letters anywhere in the image, no borders or frames, no captions or signatures";

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
