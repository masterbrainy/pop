// `reactor-token`: Orbis access for the signed-in user (docs/CONTRACTS.md §3,
// ROADMAP §2). mint ends this user's own leftover sessions first, then mints a
// 1 h / 2-session token; report records a session the app opened; cleanup ends
// this user's recorded sessions. Requires sign-in and a per-user rate limit;
// the account-wide REACTOR_API_KEY never leaves this function.
//
// reactor_sessions is server-only (REVIEW.md R-27): RLS grants the signed-in
// user's own client no access to it at all, so every read/write here goes
// through the service-role client and filters by user_id explicitly (there is
// no RLS left to do that filtering for us).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { requireUser } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/env.ts";
import { PopError } from "../_shared/errors.ts";
import { servePop } from "../_shared/handler.ts";
import { deleteReactorSession, mintReactorToken } from "../_shared/reactor_client.ts";
import { enforceStandardRateLimit } from "../_shared/rate_limit.ts";
import { parseRequest } from "../_shared/request.ts";
import { createServiceClient } from "../_shared/service_client.ts";
import { requestSchema } from "./schema.ts";
import { tokenExpiresAt } from "./expiry.ts";

const REACTOR_TOKEN_TTL_SECONDS = 3600;

interface OpenSessionRow {
  session_id: string;
}

/** Ends every open session this user is recorded as owning; returns how many closed. */
async function endThisUsersOpenSessions(
  serviceClient: SupabaseClient,
  userId: string,
  apiKey: string,
): Promise<number> {
  const { data, error } = await serviceClient
    .from("reactor_sessions")
    .select("session_id")
    .eq("user_id", userId)
    .is("ended_at", null);
  if (error) {
    throw new PopError("internal", "Failed to read this user's open Reactor sessions");
  }

  let ended = 0;
  for (const row of (data ?? []) as OpenSessionRow[]) {
    const deleted = await deleteReactorSession(apiKey, row.session_id);
    if (!deleted) continue;
    const { error: updateError } = await serviceClient
      .from("reactor_sessions")
      .update({ ended_at: new Date().toISOString() })
      .eq("session_id", row.session_id)
      .eq("user_id", userId);
    if (!updateError) ended++;
  }
  return ended;
}

type ReactorTokenData =
  | { jwt: string; expiresAt: number }
  | { recorded: true }
  | { ended: number };

Deno.serve((req) =>
  servePop<ReactorTokenData>(req, "reactor-token", async (req) => {
    const { client, userId } = await requireUser(req);
    await enforceStandardRateLimit(client, "reactor-token");
    const body = await parseRequest(req, requestSchema);
    const apiKey = requireEnv("REACTOR_API_KEY");
    const serviceClient = createServiceClient();

    if (body.action === "mint") {
      await endThisUsersOpenSessions(serviceClient, userId, apiKey);
      const { jwt } = await mintReactorToken(apiKey);
      return {
        data: { jwt, expiresAt: tokenExpiresAt(Date.now(), REACTOR_TOKEN_TTL_SECONDS) },
      };
    }

    if (body.action === "report") {
      const { error } = await serviceClient
        .from("reactor_sessions")
        .upsert(
          { session_id: body.sessionId, user_id: userId },
          { onConflict: "session_id" },
        );
      if (error) {
        throw new PopError("internal", "Failed to record the Reactor session");
      }
      return { data: { recorded: true } };
    }

    const ended = await endThisUsersOpenSessions(serviceClient, userId, apiKey);
    return { data: { ended } };
  })
);
