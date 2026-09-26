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

export const CHROMA_GREEN_HEX = "#00FF00";

export const CUTOUT_BACKGROUND_INSTRUCTION =
  `a single character, centered, full body visible, on a flat solid pure chroma-key green background (${CHROMA_GREEN_HEX}), ` +
  "no shadow cast on the background, even studio lighting on the character only";

export const PLATE_INSTRUCTION =
  "the same scene and setting with no characters present, as if they had stepped out of frame; " +
  "keep the background, props and lighting identical to the page illustration";

export type ArtKind = "page" | "cover" | "character" | "plate" | "cutout";

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
