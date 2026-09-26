// Per-user rate limiting via the public.hit_rate_limit() RPC (security definer,
// atomic upsert keyed on auth.uid()). See supabase/migrations for the SQL.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { PopError } from "./errors.ts";

export const DAY_SECONDS = 86400;
export const MINUTE_SECONDS = 60;

// Suggested per-minute limits (task brief / ROADMAP §0.6).
export const RATE_LIMITS_PER_MINUTE: Record<string, number> = {
  "story-turn": 30,
  art: 20,
  "motion-prompt": 20,
  moderate: 60,
  tts: 30,
  "stt-token": 10,
  "reactor-token": 10,
};

export const ART_DAILY_LIMIT = 300;

export async function enforceRateLimit(
  client: SupabaseClient,
  fn: string,
  limit: number,
  windowSeconds: number = MINUTE_SECONDS,
): Promise<void> {
  const { data, error } = await client.rpc("hit_rate_limit", {
    p_fn: fn,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    throw new PopError("internal", `Rate limit check failed for ${fn}`);
  }
  if (data !== true) {
    throw new PopError(
      "rate_limited",
      `Too many requests to ${fn}. Please wait a moment and try again.`,
    );
  }
}

/** Enforces this function's standard per-minute limit from RATE_LIMITS_PER_MINUTE. */
export async function enforceStandardRateLimit(
  client: SupabaseClient,
  fn: keyof typeof RATE_LIMITS_PER_MINUTE,
): Promise<void> {
  await enforceRateLimit(client, fn, RATE_LIMITS_PER_MINUTE[fn], MINUTE_SECONDS);
}
