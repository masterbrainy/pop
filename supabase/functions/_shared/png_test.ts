import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { pngDimensions } from "./png.ts";

function fakePng(width: number, height: number): Uint8Array {
  const bytes = new Uint8Array(24);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  const view = new DataView(bytes.buffer);
  view.setUint32(8, 13, false); // IHDR chunk length
  bytes.set([0x49, 0x48, 0x44, 0x52], 12); // "IHDR"
  view.setUint32(16, width, false);
  view.setUint32(20, height, false);
  return bytes;
}

Deno.test("pngDimensions reads width and height from the IHDR chunk", () => {
  assertEquals(pngDimensions(fakePng(1344, 768)), { width: 1344, height: 768 });
  assertEquals(pngDimensions(fakePng(1024, 1536)), { width: 1024, height: 1536 });
});

Deno.test("pngDimensions rejects bytes that are too short", () => {
  assertThrows(() => pngDimensions(new Uint8Array(10)), Error, "too short");
});

Deno.test("pngDimensions rejects a bad signature", () => {
  const bytes = fakePng(100, 100);
  bytes[0] = 0x00;
  assertThrows(() => pngDimensions(bytes), Error, "bad signature");
});
