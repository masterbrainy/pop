// IMP-24 guided setup: the picture-tile catalog. setup_tiles.json is the one
// source of truth (the app mirrors it in PopKit's SetupCards.swift); the app
// sends only a tile's id and this turns it into the phrase the prompt uses.
import catalog from "./setup_tiles.json" with { type: "json" };
import type { ReadingLevel } from "./reading_levels.ts";

export const SETUP_CARDS = ["hero", "place", "problem"] as const;
export type SetupCard = (typeof SETUP_CARDS)[number];

export interface SetupTile {
  readonly id: string;
  readonly card: SetupCard;
  /** May contain "{kid}", replaced by the kid's first name. */
  readonly phrase: string;
  readonly symbol: string;
  readonly levels: readonly ReadingLevel[];
}

export const SETUP_TILES: readonly SetupTile[] = catalog.tiles as SetupTile[];

const TILES_BY_ID: ReadonlyMap<string, SetupTile> = new Map(SETUP_TILES.map((tile) => [tile.id, tile]));

/**
 * The phrase for tile `id` on `card`, with "{kid}" replaced by the kid's
 * first name. null for an unknown id or a tile from another card (both are
 * ignored by the prompt, never a bad_request — docs contract).
 */
export function tilePhrase(id: string, card: SetupCard, kidFirstName: string): string | null {
  const tile = TILES_BY_ID.get(id.trim());
  if (!tile || tile.card !== card) return null;
  return tile.phrase.replaceAll("{kid}", kidFirstName);
}
