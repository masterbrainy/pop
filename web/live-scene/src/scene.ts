import { Reactor, type ConnectionStats, type ReactorError, type ReactorMessage } from "@reactor-team/js-sdk";

import { log, post } from "./bridge.ts";
import { ORBIS_MODEL_NAME, ORBIS_TRACKS, chunkIndexOf, describeMessage, unwrapOrbisMessage, type OrbisMessage } from "./orbis.ts";
import { MessageWaiters } from "./waiters.ts";

const IMAGE_READY_TIMEOUT_MS = 30_000;
/** Session start-up is measured in minutes; the starter's 15 s ceiling fired too early. */
const CONDITIONS_READY_TIMEOUT_MS = 300_000;
const COMMAND_EVENT_TIMEOUT_MS = 20_000;

export type ConnectResult = { sessionId: string | null; connectMs: number };
export type PrepareArgs = { imageUrl: string; prompt: string; seed?: number };
export type PrepareResult = { width: number | null; height: number | null; prepareMs: number };
export type VideoFit = "cover" | "contain" | "fill";

type Match = (message: OrbisMessage) => boolean;

const isImageReady: Match = (m) => m.type === "state" && m.has_image === true;
const isConditionsReady: Match = (m) => m.type === "conditions_ready";
const isGenerationStarted: Match = (m) => m.type === "generation_started";
const isResetDone: Match = (m) =>
  m.type === "generation_reset" || (m.type === "state" && m.started === false && m.has_image !== true);

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function booleanOrNull(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

async function fetchStill(url: string): Promise<Blob> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`page still ${url}: HTTP ${response.status}`);
  return response.blob();
}

/**
 * Drives one Orbis session for one page at a time:
 * reset → set_image(page still) → set_prompt → conditions_ready → start (ROADMAP §2).
 */
export class LiveSceneController {
  private reactor: Reactor | null = null;
  private readonly waiters = new MessageWaiters();
  private started = false;
  private hasImage = false;
  private startedAt: number | null = null;
  private watchingForFirstFrame = false;

  constructor(private readonly video: HTMLVideoElement) {}

  async connect(jwt: string, modelName: string = ORBIS_MODEL_NAME): Promise<ConnectResult> {
    if (this.reactor) throw new Error("already connected; disconnect first");
    const reactor = new Reactor({ modelName, jwt, modelTracks: ORBIS_TRACKS.map((track) => ({ ...track })) });
    this.reactor = reactor;
    this.wire(reactor);
    const begin = performance.now();
    try {
      await reactor.connect();
    } catch (error) {
      // A connect that fails midway can leave a billing session behind; ask the SDK to end it.
      this.reactor = null;
      await reactor.disconnect().catch((cleanup: unknown) => log(`disconnect after failed connect: ${String(cleanup)}`));
      throw error;
    }
    return { sessionId: reactor.getSessionId() ?? null, connectMs: Math.round(performance.now() - begin) };
  }

  async prepare(args: PrepareArgs): Promise<PrepareResult> {
    const reactor = this.requireReactor();
    const begin = performance.now();
    const still = await fetchStill(args.imageUrl);
    if (this.started || this.hasImage) await this.reset();
    if (args.seed !== undefined) await this.command("set_seed", { seed: args.seed });
    const file = await reactor.uploadFile(still, { name: still.type === "image/png" ? "page.png" : "page.jpg" });
    const accepted = await this.commandThenEvent("set_image", { image: file }, isImageReady, IMAGE_READY_TIMEOUT_MS, "state.has_image");
    await this.commandThenEvent("set_prompt", { prompt: args.prompt }, isConditionsReady, CONDITIONS_READY_TIMEOUT_MS, "conditions_ready");
    return {
      width: numberOrNull(accepted?.width),
      height: numberOrNull(accepted?.height),
      prepareMs: Math.round(performance.now() - begin),
    };
  }

  async start(): Promise<{ startMs: number }> {
    const begin = performance.now();
    this.startedAt = begin;
    this.watchFirstFrame();
    await this.commandThenEvent("start", {}, isGenerationStarted, COMMAND_EVENT_TIMEOUT_MS, "generation_started");
    return { startMs: Math.round(performance.now() - begin) };
  }

  async setPrompt(prompt: string): Promise<void> {
    await this.command("set_prompt", { prompt });
  }

  async pause(): Promise<void> {
    await this.command("pause");
  }

  async resume(): Promise<void> {
    await this.command("resume");
  }

  /** Clears the image and prompt and stops generation; the next page needs prepare() again. */
  async reset(): Promise<void> {
    await this.commandThenEvent("reset", {}, isResetDone, COMMAND_EVENT_TIMEOUT_MS, "reset");
    this.started = false;
    this.hasImage = false;
    this.watchingForFirstFrame = false;
    this.video.classList.remove("live");
  }

  setFit(fit: VideoFit): void {
    this.video.style.objectFit = fit;
  }

  /** Ends the session on the server (the SDK's disconnect always does) and frees the client. */
  async disconnect(): Promise<void> {
    const reactor = this.reactor;
    if (!reactor) return;
    this.reactor = null;
    this.waiters.rejectAll(new Error("disconnected"));
    this.started = false;
    this.hasImage = false;
    this.watchingForFirstFrame = false;
    this.video.classList.remove("live");
    this.video.srcObject = null;
    await reactor.disconnect();
  }

  private requireReactor(): Reactor {
    if (!this.reactor) throw new Error("not connected");
    return this.reactor;
  }

  /** Sends a command; a `command_error` reply becomes a thrown error. */
  private async command(name: string, data: Record<string, unknown> = {}): Promise<OrbisMessage | null> {
    const reply = await this.requireReactor().sendCommand(name, data);
    const message = reply ? unwrapOrbisMessage(reply) : null;
    if (message?.type === "command_error") throw new Error(`${name}: ${message.reason ?? "rejected"}`);
    return message;
  }

  /** Sends a command, then waits for the model event that confirms it took effect. */
  private async commandThenEvent(
    name: string,
    data: Record<string, unknown>,
    match: Match,
    timeoutMs: number,
    label: string,
  ): Promise<OrbisMessage | null> {
    const confirmed = this.waiters.waitFor(match, timeoutMs, label);
    try {
      const reply = await this.command(name, data);
      await confirmed;
      return reply;
    } catch (error) {
      confirmed.catch(() => undefined); // nobody waits on it any more
      throw error;
    }
  }

  private wire(reactor: Reactor): void {
    reactor.on("statusChanged", (status) => post({ event: "status", status }));
    reactor.on("sessionIdChanged", (id) => post({ event: "session", id: id ?? null }));
    reactor.on("error", (error: ReactorError) =>
      post({ event: "error", code: error.code, message: error.message, recoverable: error.recoverable }),
    );
    reactor.on("message", (raw: ReactorMessage) => this.onModelMessage(unwrapOrbisMessage(raw)));
    reactor.on("runtimeMessage", (raw: ReactorMessage) =>
      post({ event: "runtime", type: raw.type, json: describeMessage(raw.data) }),
    );
    reactor.on("schemaReceived", (schema) => post({ event: "model", type: "schema", json: describeMessage(schema) }));
    reactor.on("trackReceived", (name, track) => {
      post({ event: "track", name, kind: track.kind });
      if (name === "main_video") this.attachVideo(track);
    });
    reactor.on("statsUpdate", (stats: ConnectionStats) =>
      post({
        event: "stats",
        fps: numberOrNull(stats.framesPerSecond),
        rttMs: numberOrNull(stats.rtt),
        kbps: stats.incomingBitrate === undefined ? null : Math.round(stats.incomingBitrate / 1000),
      }),
    );
  }

  private onModelMessage(message: OrbisMessage): void {
    this.waiters.dispatch(message);
    if (message.type === "chunk_complete") {
      post({ event: "chunk", index: chunkIndexOf(message), frames: numberOrNull(message.frames_emitted) });
      return;
    }
    if (message.type === "state") {
      this.started = message.started ?? this.started;
      this.hasImage = message.has_image ?? this.hasImage;
      post({
        event: "state",
        started: booleanOrNull(message.started),
        paused: booleanOrNull(message.paused),
        hasImage: booleanOrNull(message.has_image),
        chunk: chunkIndexOf(message),
      });
      return;
    }
    if (message.type === "generation_started") this.started = true;
    if (message.type === "generation_complete" || message.type === "generation_reset") this.started = false;
    post({ event: "model", type: message.type ?? "unknown", json: describeMessage(message) });
  }

  private attachVideo(track: MediaStreamTrack): void {
    this.video.muted = true;
    this.video.srcObject = new MediaStream([track]);
    this.video.play().catch((error: unknown) => log(`video.play: ${String(error)}`));
  }

  /** Reports the first frame shown after start(), which is when the still can hand over to video. */
  private watchFirstFrame(): void {
    this.watchingForFirstFrame = true;
    this.video.classList.remove("live");
    this.video.requestVideoFrameCallback(() => {
      if (!this.watchingForFirstFrame) return;
      this.watchingForFirstFrame = false;
      this.video.classList.add("live");
      post({
        event: "firstFrame",
        sinceStartMs: this.startedAt === null ? null : Math.round(performance.now() - this.startedAt),
        width: this.video.videoWidth,
        height: this.video.videoHeight,
      });
    });
  }
}
