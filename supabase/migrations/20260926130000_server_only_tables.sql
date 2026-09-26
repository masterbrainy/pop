-- REVIEW.md R-27: rate_limits and reactor_sessions must be server-only. RLS
-- stays enabled on both (defence in depth), but with every client-facing
-- policy dropped, no row is visible or writable to `anon` or `authenticated`
-- through the Data API — only a service-role client (which bypasses RLS
-- entirely) or the SECURITY DEFINER hit_rate_limit() RPC below can touch
-- them. Without this, a signed-in user could reset their own rate-limit
-- counts or delete their reactor_sessions rows via the REST API, undoing the
-- per-user limit and reactor-token's cleanup bookkeeping (CONTRACTS.md §4).

drop policy if exists "reactor_sessions_select_own" on public.reactor_sessions;
drop policy if exists "reactor_sessions_insert_own" on public.reactor_sessions;
drop policy if exists "reactor_sessions_update_own" on public.reactor_sessions;

drop policy if exists "rate_limits_select_own" on public.rate_limits;

-- Belt and suspenders: also revoke the table-level grants Supabase's
-- auto_expose_new_tables default may have applied. RLS with zero policies
-- already blocks every row for these roles, but removing the grants means
-- there is no privilege left to misconfigure later by adding a policy back
-- without thinking it through.
revoke all on public.reactor_sessions from anon, authenticated;
revoke all on public.rate_limits from anon, authenticated;

-- hit_rate_limit() is unaffected: it is SECURITY DEFINER (runs as the
-- function owner, which bypasses RLS) and was never granted to anon, so
-- authenticated users keep working exactly as before via the RPC.
