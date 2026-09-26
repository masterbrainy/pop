// Admin-secret check for `reactor-sessions` (docs/CONTRACTS.md §3): the app
// never calls this function, so it is gated by a constant-time comparison of
// the `x-pop-admin` header against REACTOR_ADMIN_SECRET instead of Supabase
// auth. Split out from index.ts so the comparison logic is testable directly.
import { PopError } from "../_shared/errors.ts";
import { timingSafeEqualStrings } from "../_shared/timing_safe_equal.ts";

export function checkAdminHeader(provided: string | null, expected: string): void {
  if (!timingSafeEqualStrings(provided ?? "", expected)) {
    throw new PopError("forbidden", "Invalid admin secret");
  }
}
