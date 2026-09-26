import { assertEquals } from "jsr:@std/assert@1";
import { sniffImageMimeType } from "./image_format.ts";

const PNG_BYTES = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const JPEG_BYTES = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);
const GIF_BYTES = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);

Deno.test("sniffImageMimeType recognises a PNG signature", () => {
  assertEquals(sniffImageMimeType(PNG_BYTES), "image/png");
});

Deno.test("sniffImageMimeType recognises a JPEG signature", () => {
  assertEquals(sniffImageMimeType(JPEG_BYTES), "image/jpeg");
});

Deno.test("sniffImageMimeType returns null for an unrecognised format", () => {
  assertEquals(sniffImageMimeType(GIF_BYTES), null);
});

Deno.test("sniffImageMimeType returns null for bytes too short to match either signature", () => {
  assertEquals(sniffImageMimeType(new Uint8Array([0x89, 0x50])), null);
});
