// Reads width/height straight from a PNG's IHDR chunk. Avoids pulling in an
// image library just to report the dimensions the `art` function already has
// the bytes for.

export interface PngDimensions {
  width: number;
  height: number;
}

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

export function pngDimensions(bytes: Uint8Array): PngDimensions {
  if (bytes.length < 24) {
    throw new Error("Not a valid PNG: too short to contain an IHDR chunk");
  }
  const hasSignature = PNG_SIGNATURE.every((byte, i) => bytes[i] === byte);
  if (!hasSignature) {
    throw new Error("Not a valid PNG: bad signature");
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  // IHDR is always the first chunk: 8-byte signature, 4-byte length, 4-byte
  // "IHDR" type, then width (4 bytes) and height (4 bytes), all big-endian.
  const width = view.getUint32(16, false);
  const height = view.getUint32(20, false);
  return { width, height };
}
