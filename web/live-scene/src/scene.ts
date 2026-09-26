import { Reactor, type ConnectionStats, type ReactorError, type ReactorMessage } from "@reactor-team/js-sdk";

import { log, post } from "./bridge.ts";
import { ORBIS_MODEL_NAME, ORBIS_TRACKS, chunkIndexOf, describeMessage, unwrapOrbisMessage, type OrbisMessage } from "./orbis.ts";
import { ClipRecorder, type ClipResult } from "./clip.ts";
import { MessageWaiters } from "./waiters.ts";
import { type FrameResult, sampleFrame } from "./frame.ts";
import { FirstFrameWatch, GenerationGate, conditionsReadyTimeoutMs } from "./gate.ts";
import { DELIVERY_COMMANDS } from "./orbis.ts";

const IMAGE_READY_TIMEOUT_MS = 30_000;
const COMMAND_EVENT_TIMEOUT_MS = 20_000;

export type ConnectResult = { sessionId: string | null; connectMs: number };
/** `generation` numbers page flows (newest wins); Swift passes one, the probe may not. */
export type PrepareArgs = { imageUrl: string; prompt: string; seed?: number; generation?: number };
export type PrepareResult = { width: number | null; height: number | null; prepareMs: number; generation: number };
export type StartArgs = { generation?: number };
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
  /** A newer page flow ends the older one's waits at once, so their events can't cross. */
  private readonly gate = new GenerationGate((superseded) => this.waiters.rejectAll(superseded));
  private readonly firstFrames = new FirstFrameWatch();
  private frameLoopActive = false;
  private started = false;
  private hasImage = false;
  /** Set once anything page-specific was sent; the next page resets first even if no state echoed it yet. */
  private sessionDirty = false;
  /** The first page on a connection may wait for the model to warm; later ones get a short timeout. */
  private preparedOnSession = false;
  private startedAt: number | null = null;
  private readonly clips = new ClipRecorder();

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
    this.preparedOnSession = false;
    this.sessionDirty = false;
    await this.configureDelivery();
    return { sessionId: reactor.getSessionId() ?? null, connectMs: Math.round(performance.now() - begin) };
  }

  /**
   * reset (if needed) → set_image(page still) → set_prompt → conditions_ready, as page flow
   * `generation`. A newer prepare supersedes this one: its waits end and it throws
   * "superseded: …" at its next step, before it sends anything else.
   */
  prepare(args: PrepareArgs): Promise<PrepareResult> {
    const generation = args.generation ?? this.gate.next();
    // A stale prepare is rejected by claim() and must not disturb the current page's watch.
    if (generation > this.gate.latest) this.firstFrames.cancel();
    return this.gate.claim(generation, async (guard) => {
      const reactor = this.requireReactor();
      const begin = performance.now();
      const still = await fetchStill(args.imageUrl);
      guard();
      this.video.classList.remove("live");
      if (this.started || this.hasImage || this.sessionDirty) await this.reset();
      guard();
      this.sessionDirty = true;
      if (args.seed !== undefined) await this.command("set_seed", { seed: args.seed });
      guard();
      const file = await reactor.uploadFile(still, { name: still.type === "image/png" ? "page.png" : "page.jpg" });
      guard();
      const accepted = await this.commandThenEvent("set_image", { image: file }, isImageReady, IMAGE_READY_TIMEOUT_MS, "state.has_image");
      guard();
      const readyTimeout = conditionsReadyTimeoutMs({ firstPageOnSession: !this.preparedOnSession });
      await this.commandThenEvent("set_prompt", { prompt: args.prompt }, isConditionsReady, readyTimeout, "conditions_ready");
      guard();
      this.preparedOnSession = true;
      return {
        width: numberOrNull(accepted?.width),
        height: numberOrNull(accepted?.height),
        prepareMs: Math.round(performance.now() - begin),
        generation,
      };
    });
  }

  /** Starts page flow `generation` (the newest prepared one); its first frame is reported with it. */
  start(args: StartArgs = {}): Promise<{ startMs: number; generation: number }> {
    const generation = args.generation ?? this.gate.latest;
    return this.gate.follow(generation, async (guard) => {
      const begin = performance.now();
      this.startedAt = begin;
      this.watchFirstFrame(generation);
      try {
        await this.commandThenEvent("start", {}, isGenerationStarted, COMMAND_EVENT_TIMEOUT_MS, "generation_started");
        guard();
      } catch (error) {
        if (this.gate.isCurrent(generation)) this.firstFrames.cancel();
        throw error;
      }
      return { startMs: Math.round(performance.now() - begin), generation };
    });
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
    this.clips.cancel();
    await this.commandThenEvent("reset", {}, isResetDone, COMMAND_EVENT_TIMEOUT_MS, "reset");
    this.started = false;
    this.hasImage = false;
    this.sessionDirty = false;
    this.firstFrames.cancel();
    this.video.classList.remove("live");
  }

  /** Records the video now playing for up to `maxSeconds`; `stopClip` sends it to Swift. */
  startClip(maxSeconds: number): void {
    const stream = this.video.srcObject;
    if (!(stream instanceof MediaStream)) throw new Error("no video to record");
    this.clips.start(stream, maxSeconds);
  }

  async stopClip(): Promise<ClipResult> {
    return this.clips.stop();
  }

  cancelClip(): void {
    this.clips.cancel();
  }

  /** The frame now showing as a small JPEG, for the moderation tripwire. */
  sampleFrame(maxSide: number): FrameResult {
    return sampleFrame(this.video, maxSide);
  }

  setFit(fit: VideoFit): void {
    this.video.style.objectFit = fit;
  }

  /** Ends the session on the server (the SDK's disconnect always does) and frees the client. */
  async disconnect(): Promise<void> {
    const reactor = this.reactor;
    if (!reactor) return;
    this.reactor = null;
    this.clips.cancel();
    this.waiters.rejectAll(new Error("disconnected"));
    this.started = false;
    this.hasImage = false;
    this.sessionDirty = false;
    this.preparedOnSession = false;
    this.firstFrames.cancel();
    this.video.classList.remove("live");
    this.video.srcObject = null;
    await reactor.disconnect();
  }

  /** Best effort: a model that rejects one of these still animates, just at its defaults. */
  private async configureDelivery(): Promise<void> {
    for (const { name, data } of DELIVERY_COMMANDS) {
      try {
        await this.command(name, data);
      } catch (error) {
        log(`${name} not applied: ${String(error)}`);
      }
    }
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
    if (message.type === "generation_started") {
      this.started = true;
      this.firstFrames.generationStarted();
    }
    if (message.type === "generation_complete" || message.type === "generation_reset") this.started = false;
    post({ event: "model", type: message.type ?? "unknown", json: describeMessage(message) });
  }

  private attachVideo(track: MediaStreamTrack): void {
    this.video.muted = true;
    this.video.srcObject = new MediaStream([track]);
    this.video.play().catch((error: unknown) => log(`video.play: ${String(error)}`));
  }

  /**
   * Reports generation `generation`'s first frame, which is when the still can hand over to
   * video. Frames shown before its `generation_started` are leftovers and don't count.
   */
  private watchFirstFrame(generation: number): void {
    this.firstFrames.arm(generation);
    this.video.classList.remove("live");
    if (this.frameLoopActive) return;
    this.frameLoopActive = true;
    const onFrame = (): void => {
      if (!this.firstFrames.isWatching) {
        this.frameLoopActive = false;
        return;
      }
      const shown = this.firstFrames.onFrame();
      if (shown === null) {
        this.video.requestVideoFrameCallback(onFrame);
        return;
      }
      this.frameLoopActive = false;
      this.video.classList.add("live");
      post({
        event: "firstFrame",
        generation: shown,
        sinceStartMs: this.startedAt === null ? null : Math.round(performance.now() - this.startedAt),
        width: this.video.videoWidth,
        height: this.video.videoHeight,
      });
    };
    this.video.requestVideoFrameCallback(onFrame);
  }
}
