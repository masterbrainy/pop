// Orbis model constants and message helpers. Ported from the teammate's
// orbis-hackathon-starter (lib/orbis.ts), used with permission (ROADMAP §4).

export const ORBIS_MODEL_NAME = "reactor/visko-orbis-stable";

/** Both tracks are receive-only. Pop! never plays the audio track while creating. */
export const ORBIS_TRACKS = [
  { name: "main_video", kind: "video", direction: "recvonly" },
  { name: "main_audio", kind: "audio", direction: "recvonly" },
] as const;

export type OrbisMessage = {
  type?: string;
  command?: string;
  reason?: string;
  width?: number;
  height?: number;
  has_image?: boolean;
  has_prompt?: boolean;
  image_conditioned?: boolean;
  started?: boolean;
  paused?: boolean;
  running?: boolean;
  prompt?: string;
  /** chunk_complete: the API reference says `session_chunk`; the wire sends `chunk_index`. */
  chunk_index?: number;
  session_chunk?: number;
  /** state: the same counter, mirrored on every snapshot. */
  current_chunk?: number;
  /** chunk_complete: frames in this chunk (the first chunk after start has none). */
  frames_emitted?: number;
  [key: string]: unknown;
};

/** Model messages arrive either bare or as `{ type, data }`; flatten to one object. */
export function unwrapOrbisMessage(raw: unknown): OrbisMessage {
  if (raw === null || typeof raw !== "object") return {};
  const envelope = raw as { type?: unknown; data?: unknown };
  if (envelope.data !== null && typeof envelope.data === "object" && !Array.isArray(envelope.data)) {
    const type = typeof envelope.type === "string" ? envelope.type : undefined;
    return { ...(envelope.data as Record<string, unknown>), type };
  }
  return raw as OrbisMessage;
}

/** The chunk counter, whichever field name this build of the model uses. */
export function chunkIndexOf(message: OrbisMessage): number | null {
  if (typeof message.chunk_index === "number") return message.chunk_index;
  if (typeof message.session_chunk === "number") return message.session_chunk;
  if (typeof message.current_chunk === "number") return message.current_chunk;
  return null;
}

const MAX_FORWARDED_JSON = 2_000;

/** A bounded JSON copy of a message for the native log; never throws. */
export function describeMessage(message: unknown): string {
  let text: string;
  try {
    text = JSON.stringify(message) ?? String(message);
  } catch {
    text = String(message);
  }
  return text.length > MAX_FORWARDED_JSON ? `${text.slice(0, MAX_FORWARDED_JSON)}…` : text;
}
