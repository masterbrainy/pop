// Events the page sends to Swift through `window.webkit.messageHandlers.pop`.
// Swift decodes them in PopKit's `SceneEvent`; keep the two in step.

export type SceneEvent =
  | { event: "loaded"; secureContext: boolean; webRTC: boolean; wasm: boolean }
  | { event: "status"; status: string }
  | { event: "session"; id: string | null }
  | { event: "track"; name: string; kind: string }
  | { event: "state"; started: boolean | null; paused: boolean | null; hasImage: boolean | null; chunk: number | null }
  | { event: "chunk"; index: number | null; frames: number | null }
  | { event: "model"; type: string; json: string }
  | { event: "runtime"; type: string; json: string }
  | { event: "firstFrame"; sinceStartMs: number | null; width: number; height: number }
  | { event: "stats"; fps: number | null; rttMs: number | null; kbps: number | null }
  | { event: "error"; code: string; message: string; recoverable: boolean }
  | { event: "log"; text: string };

type MessageHandler = { postMessage(message: unknown): void };

function nativeHandler(): MessageHandler | null {
  const webkit = (window as unknown as { webkit?: { messageHandlers?: Record<string, MessageHandler> } }).webkit;
  return webkit?.messageHandlers?.pop ?? null;
}

/** Sends one event to Swift; falls back to the console when opened in a desktop browser. */
export function post(message: SceneEvent): void {
  const handler = nativeHandler();
  if (handler) {
    handler.postMessage(message);
  } else {
    console.log("[popScene]", message);
  }
}

export function log(text: string): void {
  post({ event: "log", text });
}
