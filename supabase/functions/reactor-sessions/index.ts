// `reactor-sessions`: admin-only account-wide Reactor session cleanup
// (docs/CONTRACTS.md §3, ROADMAP §2). The app never calls this; the run-book
// does, after a demo. Gated by a constant-time check of `x-pop-admin` against
// REACTOR_ADMIN_SECRET rather than Supabase auth — deployed with
// `verify_jwt = false` (see supabase/config.toml). No DB access: it only
// reflects Reactor's own account-wide session list.
import { requireEnv } from "../_shared/env.ts";
import { servePop } from "../_shared/handler.ts";
import { deleteReactorSession, listOpenReactorSessions } from "../_shared/reactor_client.ts";
import { parseRequest } from "../_shared/request.ts";
import { checkAdminHeader } from "./admin.ts";
import { requestSchema } from "./schema.ts";

type ReactorSessionsData =
  | { open: { sessionId: string; state: string }[] }
  | { ended: number };

Deno.serve((req) =>
  servePop<ReactorSessionsData>(req, "reactor-sessions", async (req) => {
    checkAdminHeader(req.headers.get("x-pop-admin"), requireEnv("REACTOR_ADMIN_SECRET"));
    const { action } = await parseRequest(req, requestSchema);
    const apiKey = requireEnv("REACTOR_API_KEY");

    const open = await listOpenReactorSessions(apiKey);

    if (action === "list") {
      return {
        data: { open: open.map((s) => ({ sessionId: s.session_id, state: s.state })) },
      };
    }

    let ended = 0;
    for (const session of open) {
      if (await deleteReactorSession(apiKey, session.session_id)) ended++;
    }
    return { data: { ended } };
  })
);
