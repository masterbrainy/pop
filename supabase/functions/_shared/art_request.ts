// `art`'s own prompt- and reference-image-selection logic (docs/CONTRACTS.md
// §3 `art`, PRD P2). Pure functions so the picking logic is unit-testable
// without any network call; index.ts does the actual image call and Storage
// download/upload.
import { decodeBase64 } from "jsr:@std/encoding@1/base64";
import { ART_STYLE, CUTOUT_BACKGROUND_INSTRUCTION, DRAWING_INSTRUCTION, PLATE_INSTRUCTION } from "./art_style.ts";
import type { ArtKind } from "./art_style.ts";
import type { InlineImage } from "./openai_images.ts";
import { sniffImageMimeType } from "./image_format.ts";
import type { Character } from "./schemas.ts";

/** Declared placeholder dimensions when moderation blocks both attempts (no picture is generated); OpenAI's sizes. */
export const STANDARD_DIMENSIONS: Record<"16:9" | "2:3" | "1:1", { width: number; height: number }> = {
  "16:9": { width: 1536, height: 1024 },
  "2:3": { width: 1024, height: 1536 },
  "1:1": { width: 1024, height: 1024 },
};

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Whole-word, case-insensitive: `phrase` with no letter, digit or underscore right before or after it, so "Rusty" never matches "Rustyville". */
function mentions(prompt: string, phrase: string): boolean {
  const trimmed = phrase.trim();
  if (trimmed === "") return false;
  const body = trimmed.split(/\s+/).map(escapeRegExp).join("\\s+");
  return new RegExp(`(?<![\\p{L}\\p{N}_])${body}(?![\\p{L}\\p{N}_])`, "iu").test(prompt);
}

/**
 * The bible characters a page's art prompt names, by their whole name
 * ("Bella the bunny") or their id ("bella"). A page picture draws only these:
 * sending every bible character, and every reference image, painted
 * characters into pages they aren't on. The story prompt asks the model to
 * name each character on the page by its bible name (story_prompt.ts).
 */
export function charactersIn(prompt: string, characters: Character[]): Character[] {
  return characters.filter((c) => mentions(prompt, c.name) || mentions(prompt, c.id));
}

/**
 * Which of this request's characters need their reference image sent to
 * the image model for consistency: the single named character for `character`/`cutout`,
 * every character with a saved reference for `cover`, only those the prompt
 * names for `page` (charactersIn), none for `plate` (which draws the scene with
 * no characters at all).
 */
export function referencePathsFor(
  kind: ArtKind,
  characters: Character[],
  characterId?: string | null,
  prompt = "",
): string[] {
  const withReference = (list: Character[]) => list.filter((c) => c.referencePath).map((c) => c.referencePath as string);
  switch (kind) {
    case "character":
    case "cutout": {
      const match = characters.find((c) => c.id === characterId && c.referencePath);
      return match?.referencePath ? [match.referencePath] : [];
    }
    case "page":
      return withReference(charactersIn(prompt, characters));
    case "cover":
      return withReference(characters);
    case "plate":
    case "drawing":
      // `plate` draws no characters at all; `drawing`'s only "reference" is
      // the kid's own drawing, attached separately by drawingInlineImage —
      // there's no existing character reference to look up yet.
      return [];
  }
}

/**
 * For `kind: "drawing"` only: decodes the kid's drawing and sniffs its image
 * format, ready to attach to the image request as a reference
 * alongside (or instead of) any stored character references. Pure and
 * network-free so it's unit-testable; `index.ts` pushes the result onto the
 * same `referenceImages` array `loadReferenceImages` builds from storage.
 * Returns `undefined` for every other kind, or when no drawing was sent
 * (schema validation already guarantees a valid one is present for `drawing`).
 */
export function drawingInlineImage(kind: ArtKind, drawing?: string | null): InlineImage | undefined {
  if (kind !== "drawing" || !drawing) return undefined;
  const bytes = decodeBase64(drawing);
  const mimeType = sniffImageMimeType(bytes) ?? "image/png";
  return { mimeType, data: drawing };
}

/** Builds the full image prompt: the locked style, kind-specific instructions, character notes, then the caller's own prompt. */
export function buildArtPrompt(
  kind: ArtKind,
  prompt: string,
  characters: Character[],
  characterId?: string | null,
): string {
  const lines: string[] = [ART_STYLE];

  if (kind === "cutout") lines.push(CUTOUT_BACKGROUND_INSTRUCTION);
  if (kind === "plate") lines.push(PLATE_INSTRUCTION);
  if (kind === "drawing") lines.push(DRAWING_INSTRUCTION);

  if (kind === "cutout" || kind === "character") {
    const character = characters.find((c) => c.id === characterId);
    if (character) lines.push(`This character: ${character.name} — ${character.description}`);
  } else if (kind === "page" || kind === "cover") {
    // A cover shows the whole cast; a page only the characters its prompt names.
    const appearing = kind === "page" ? charactersIn(prompt, characters) : characters;
    if (appearing.length > 0) {
      lines.push(
        "Characters appearing in this picture — keep each one's look identical to its reference image if one is attached: " +
          appearing.map((c) => `${c.name} (${c.description})`).join("; "),
      );
    }
  }

  lines.push(prompt);
  return lines.join("\n\n");
}

/** Appended on the one regeneration attempt after a moderation flag (PRD §8.6 responses). */
export const SAFER_REGENERATION_SUFFIX =
  "Make this version gentler and calmer, suitable for a young child: avoid anything that could be scary, violent or otherwise unsafe.";
