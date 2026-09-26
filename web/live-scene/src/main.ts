// Entry point of the page Pop! loads into its WKWebView (popscene://app/live-scene.html).
// Swift drives it through `window.popScene` with callAsyncJavaScript, and hears back
// through `window.webkit.messageHandlers.pop` (see bridge.ts).

import { post } from "./bridge.ts";
import { LiveSceneController, type PrepareArgs, type VideoFit } from "./scene.ts";

const video = document.getElementById("scene");
if (!(video instanceof HTMLVideoElement)) throw new Error("live-scene.html has no <video id=\"scene\">");

const controller = new LiveSceneController(video);

const popScene = {
  connect: (args: { jwt: string; modelName?: string }) => controller.connect(args.jwt, args.modelName),
  prepare: (args: PrepareArgs) => controller.prepare(args),
  start: () => controller.start(),
  setPrompt: (args: { prompt: string }) => controller.setPrompt(args.prompt),
  pause: () => controller.pause(),
  resume: () => controller.resume(),
  reset: () => controller.reset(),
  setFit: (args: { fit: VideoFit }) => controller.setFit(args.fit),
  startClip: (args: { maxSeconds: number }) => controller.startClip(args.maxSeconds),
  stopClip: () => controller.stopClip(),
  cancelClip: () => controller.cancelClip(),
  sampleFrame: (args: { maxSide: number }) => controller.sampleFrame(args.maxSide),
  disconnect: () => controller.disconnect(),
};

declare global {
  interface Window {
    popScene?: typeof popScene;
  }
}

window.popScene = popScene;

window.addEventListener("error", (event) =>
  post({ event: "error", code: "js", message: String(event.message), recoverable: false }),
);
window.addEventListener("unhandledrejection", (event) =>
  post({ event: "error", code: "js.unhandled", message: String(event.reason), recoverable: false }),
);

post({
  event: "loaded",
  secureContext: window.isSecureContext,
  webRTC: typeof RTCPeerConnection === "function",
  wasm: typeof WebAssembly === "object",
});
