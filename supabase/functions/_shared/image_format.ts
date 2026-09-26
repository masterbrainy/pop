// Sniffs an image's format from its own magic bytes. Used by `art`'s
// `drawing` kind (docs/CONTRACTS.md §3), which accepts a kid's finger
// drawing as PNG or JPEG with no separate mimeType field — unlike `moderate`,
// which takes mimeType from the caller. Kept separate from png.ts, whose job
// is reading a *known* PNG's own IHDR dimensions, not classifying arbitrary
// bytes into a format.

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG_SIGNATURE = [0xff, 0xd8, 0xff];

function startsWith(bytes: Uint8Array, signature: number[]): boolean {
  return signature.every((byte, i) => bytes[i] === byte);
}

/** Returns the sniffed mime type, or `null` if the bytes are neither a PNG nor a JPEG. */
export function sniffImageMimeType(bytes: Uint8Array): "image/png" | "image/jpeg" | null {
  if (startsWith(bytes, PNG_SIGNATURE)) return "image/png";
  if (startsWith(bytes, JPEG_SIGNATURE)) return "image/jpeg";
  return null;
}
