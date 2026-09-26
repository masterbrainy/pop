// Samples the video now showing as a small JPEG, so Swift can send it through image
// moderation (the frame tripwire, ROADMAP Phase 3). A snapshot of the WKWebView doesn't
// capture WebRTC video, so the frame is drawn to a canvas here.

export type FrameResult = { mimeType: string; base64: string; width: number; height: number };

const JPEG_QUALITY = 0.7;

/** The size to draw a `width`×`height` frame at, with its long side at most `maxSide`. */
export function frameSize(width: number, height: number, maxSide: number): { width: number; height: number } | null {
  if (width <= 0 || height <= 0) return null;
  const scale = Math.min(1, maxSide / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/** Splits a base64 `data:` URL into its type and payload. */
export function stripDataUrl(url: string): { mimeType: string; base64: string } | null {
  const match = /^data:([^;,]+);base64,(.+)$/.exec(url);
  const [, mimeType, base64] = match ?? [];
  if (!mimeType || !base64) return null;
  return { mimeType, base64 };
}

/** Draws the current frame of `video` and returns it as a JPEG. */
export function sampleFrame(video: HTMLVideoElement, maxSide: number): FrameResult {
  const size = frameSize(video.videoWidth, video.videoHeight, maxSide);
  if (!size) throw new Error("no video frame to sample");
  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("no 2D canvas");
  context.drawImage(video, 0, 0, size.width, size.height);
  const parts = stripDataUrl(canvas.toDataURL("image/jpeg", JPEG_QUALITY));
  if (!parts) throw new Error("frame encoding failed");
  return { ...parts, ...size };
}
