// Storage helpers for the private `pop-books` bucket. Every call uses the
// caller's own RLS-scoped client (see auth.ts), so a user can only ever touch
// objects under their own `<userId>/…` prefix — enforced twice, by storage RLS
// policy and by this path builder always starting with that user's id.
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import type { ArtKind } from "./art_style.ts";
import { PopError } from "./errors.ts";

export const POP_BOOKS_BUCKET = "pop-books";
// CONTRACTS.md §3 `art`: "url, signed URL, 1 h".
export const SIGNED_URL_TTL_SECONDS = 60 * 60;

export interface ArtObjectPathInput {
  userId: string;
  bookId: string;
  kind: ArtKind;
  version: number;
  pageIndex?: number;
  characterId?: string;
}

function requireField<T>(value: T | undefined, field: string, kind: ArtKind): T {
  if (value === undefined || value === null) {
    throw new PopError("bad_request", `${field} is required for art kind "${kind}"`);
  }
  return value;
}

/**
 * `<userId>/<bookId>/…png` (CONTRACTS.md §1, §4). `page` and `plate` are keyed
 * by page index; `cutout` by character and page; `cover` and `character` have
 * no page index, so they get their own naming.
 */
export function artObjectPath(input: ArtObjectPathInput): string {
  const prefix = `${input.userId}/${input.bookId}`;
  switch (input.kind) {
    case "cover":
      return `${prefix}/cover-v${input.version}.png`;
    case "character":
      return `${prefix}/character-${requireField(input.characterId, "characterId", input.kind)}-v${input.version}.png`;
    case "page":
      return `${prefix}/page-${requireField(input.pageIndex, "pageIndex", input.kind)}-v${input.version}.png`;
    case "plate":
      return `${prefix}/plate-${requireField(input.pageIndex, "pageIndex", input.kind)}-v${input.version}.png`;
    case "cutout":
      return `${prefix}/cutout-${requireField(input.characterId, "characterId", input.kind)}-${
        requireField(input.pageIndex, "pageIndex", input.kind)
      }-v${input.version}.png`;
  }
}

export async function uploadPng(
  client: SupabaseClient,
  path: string,
  bytes: Uint8Array,
): Promise<void> {
  const { error } = await client.storage.from(POP_BOOKS_BUCKET).upload(path, bytes, {
    contentType: "image/png",
    upsert: true,
  });
  if (error) {
    throw new PopError("internal", "Failed to store the generated image");
  }
}

export async function createSignedUrl(
  client: SupabaseClient,
  path: string,
): Promise<string> {
  const { data, error } = await client.storage
    .from(POP_BOOKS_BUCKET)
    .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
  if (error || !data?.signedUrl) {
    throw new PopError("internal", "Failed to create a signed URL");
  }
  return data.signedUrl;
}

export async function downloadAsBase64(
  client: SupabaseClient,
  path: string,
): Promise<{ base64: string; mimeType: string }> {
  const { data, error } = await client.storage.from(POP_BOOKS_BUCKET).download(path);
  if (error || !data) {
    throw new PopError("bad_request", `Could not read the stored file at ${path}`);
  }
  const buffer = new Uint8Array(await data.arrayBuffer());
  return { base64: encodeBase64(buffer), mimeType: data.type || "image/png" };
}
