// A service-role client, for the two tables that REVIEW.md R-27 made
// server-only (rate_limits, reactor_sessions): RLS on those tables now grants
// the `anon`/`authenticated` roles no access at all, so functions that read
// or write them must use the service role, which bypasses RLS, and must
// filter by user id themselves in every query (there is no RLS left to do it
// for them).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { requireEnv } from "./env.ts";

export function createServiceClient(): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
