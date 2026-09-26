// Records the page's Orbis video into a clip so a saved book replays exactly (ROADMAP 0.3b, D4).
// The bytes go to Swift in base64 chunks through `window.webkit.messageHandlers.popClip`,
// because a WKWebView can't hand a Blob to native code directly.

const CHUNK_BYTES = 256 * 1024;
const PREFERRED_TYPES = ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp8", "video/webm"];

export type ClipResult = { clipId: string; bytes: number; mimeType: string; durationMs: number; chunks: number };

type ClipMessage =
  | { clipId: string; seq: number; base64: string; last: false }
  | { clipId: string; seq: number; base64: string; last: true; mimeType: string; bytes: number; durationMs: number };

type MessageHandler = { postMessage(message: unknown): void };

function clipHandler(): MessageHandler | null {
  const webkit = (window as unknown as { webkit?: { messageHandlers?: Record<string, MessageHandler> } }).webkit;
  return webkit?.messageHandlers?.popClip ?? null;
}

export function pickMimeType(isSupported: (type: string) => boolean): string | null {
  return PREFERRED_TYPES.find((type) => isSupported(type)) ?? null;
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const step = 0x8000;
  for (let i = 0; i < bytes.length; i += step) {
    binary += String.fromCharCode(...bytes.subarray(i, i + step));
  }
  return btoa(binary);
}

export function chunkCount(byteLength: number): number {
  return Math.max(1, Math.ceil(byteLength / CHUNK_BYTES));
}

export class ClipRecorder {
  private recorder: MediaRecorder | null = null;
  private parts: Blob[] = [];
  private startedAt = 0;
  private stopTimer: ReturnType<typeof setTimeout> | null = null;
  private finished: Promise<ClipResult> | null = null;

  get recording(): boolean {
    return this.recorder !== null;
  }

  /** Starts recording `stream`; stops by itself after `maxSeconds` (the clip is then sent). */
  start(stream: MediaStream, maxSeconds: number): void {
    if (this.recorder || this.finished) throw new Error("already recording a clip");
    const mimeType = pickMimeType((type) => MediaRecorder.isTypeSupported(type));
    if (!mimeType) throw new Error("MediaRecorder supports none of the clip formats");
    const recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 2_500_000 });
    this.recorder = recorder;
    this.parts = [];
    this.startedAt = performance.now();
    const clipId = crypto.randomUUID();
    this.finished = new Promise<ClipResult>((resolve, reject) => {
      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) this.parts.push(event.data);
      };
      recorder.onerror = () => reject(new Error("MediaRecorder failed"));
      recorder.onstop = () => {
        const durationMs = Math.round(performance.now() - this.startedAt);
        const blob = new Blob(this.parts, { type: mimeType });
        this.parts = [];
        this.send(clipId, blob, mimeType, durationMs).then(resolve, reject);
      };
    });
    recorder.start(1000);
    this.stopTimer = setTimeout(() => this.stopRecorder(), maxSeconds * 1000);
  }

  /** Stops recording (if it hasn't already) and resolves once every chunk has reached Swift. */
  async stop(): Promise<ClipResult> {
    const finished = this.finished;
    if (!finished) throw new Error("no clip is recording");
    this.stopRecorder();
    try {
      return await finished;
    } finally {
      this.finished = null;
    }
  }

  /** Throws the recording away (the page turned before its clip completed). */
  cancel(): void {
    if (this.stopTimer) clearTimeout(this.stopTimer);
    this.stopTimer = null;
    const recorder = this.recorder;
    this.recorder = null;
    this.finished?.catch(() => undefined);
    this.finished = null;
    this.parts = [];
    if (recorder && recorder.state !== "inactive") {
      recorder.onstop = null;
      recorder.stop();
    }
  }

  private stopRecorder(): void {
    if (this.stopTimer) clearTimeout(this.stopTimer);
    this.stopTimer = null;
    const recorder = this.recorder;
    this.recorder = null;
    if (recorder && recorder.state !== "inactive") recorder.stop();
  }

  private async send(clipId: string, blob: Blob, mimeType: string, durationMs: number): Promise<ClipResult> {
    const handler = clipHandler();
    const bytes = new Uint8Array(await blob.arrayBuffer());
    const chunks = chunkCount(bytes.length);
    for (let seq = 0; seq < chunks; seq += 1) {
      const slice = bytes.subarray(seq * CHUNK_BYTES, (seq + 1) * CHUNK_BYTES);
      const base64 = toBase64(slice);
      const message: ClipMessage =
        seq === chunks - 1
          ? { clipId, seq, base64, last: true, mimeType, bytes: bytes.length, durationMs }
          : { clipId, seq, base64, last: false };
      handler?.postMessage(message);
    }
    return { clipId, bytes: bytes.length, mimeType, durationMs, chunks };
  }
}
