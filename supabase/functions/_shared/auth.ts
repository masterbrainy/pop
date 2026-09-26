// Resolves the calling user from the bearer token (docs/CONTRACTS.md §3: every
// function is called with the anonymous user's access token). The returned
// client carries that same token, so every DB/storage call it makes is
// RLS-scoped to this user — functions never need a service-role key.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { PopError } from "./errors.ts";
import { requireEnv } from "./env.ts";

export interface AuthedUser {
  client: SupabaseClient;
  userId: string;
}

export async function requireUser(req: Request): Promise<AuthedUser> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !/^Bearer\s+\S+/i.test(authHeader)) {
    throw new PopError("unauthorized", "Missing or malformed Authorization header");
  }

  const client = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );

  const { data, error } = await client.auth.getUser();
  if (error || !data?.user) {
    throw new PopError("unauthorized", "Invalid or expired session");
  }

  return { client, userId: data.user.id };
}
