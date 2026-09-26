// Reactor Orbis session/token admin client (ROADMAP §2, §4; ported from the
// teammate's Next.js starter — see the task brief for the source paths). Every
// call needs the account-wide REACTOR_API_KEY, so it never appears in a
// user-facing error and is read once by the caller and passed in explicitly.
import { PopError } from "./errors.ts";
import { REACTOR_MODEL } from "./models.ts";

export const REACTOR_API_URL = "https://api.reactor.inc";

export interface MintTokenRequestBody {
  expires_after: number;
  authorization_details: [{
    type: "session";
    resources: { models: { match: [string] } };
    constraints: { max_sessions: number };
  }];
}

/** 1 h / 2 sessions per CONTRACTS.md §3 `reactor-token`. */
export function buildMintTokenRequestBody(
  maxSessions = 2,
  expiresAfterSeconds = 3600,
): MintTokenRequestBody {
  return {
    expires_after: expiresAfterSeconds,
    authorization_details: [{
      type: "session",
      resources: { models: { match: [REACTOR_MODEL] } },
      constraints: { max_sessions: maxSessions },
    }],
  };
}

function reactorHeaders(apiKey: string): HeadersInit {
  return { "Content-Type": "application/json", "Reactor-API-Key": apiKey };
}

export async function mintReactorToken(
  apiKey: string,
): Promise<{ jwt: string }> {
  const res = await fetch(`${REACTOR_API_URL}/tokens`, {
    method: "POST",
    headers: reactorHeaders(apiKey),
    body: JSON.stringify(buildMintTokenRequestBody()),
  });
  if (!res.ok) {
    throw new PopError("upstream", `Reactor token request failed (${res.status})`);
  }
  const body = await res.json() as { jwt?: string };
  if (!body.jwt) {
    throw new PopError("upstream", "Reactor returned no token");
  }
  return { jwt: body.jwt };
}

async function reactorAccountId(apiKey: string): Promise<string> {
  const res = await fetch(`${REACTOR_API_URL}/me`, { headers: reactorHeaders(apiKey) });
  if (!res.ok) {
    throw new PopError("upstream", `Reactor account lookup failed (${res.status})`);
  }
  const body = await res.json() as { account_id?: string };
  if (!body.account_id) {
    throw new PopError("upstream", "Reactor account lookup returned no account id");
  }
  return body.account_id;
}

export interface ReactorSession {
  session_id: string;
  model: string;
  state: string;
  closed: boolean;
}

export async function listOpenReactorSessions(
  apiKey: string,
): Promise<ReactorSession[]> {
  const account = await reactorAccountId(apiKey);
  const res = await fetch(`${REACTOR_API_URL}/accounts/${account}/sessions`, {
    headers: reactorHeaders(apiKey),
  });
  if (!res.ok) {
    throw new PopError("upstream", `Reactor session list failed (${res.status})`);
  }
  const body = await res.json() as { sessions?: ReactorSession[] };
  return (body.sessions ?? []).filter((session) => !session.closed);
}

/** Best-effort delete; the caller decides how to report a failed id. */
export async function deleteReactorSession(
  apiKey: string,
  sessionId: string,
): Promise<boolean> {
  const res = await fetch(`${REACTOR_API_URL}/sessions/${sessionId}`, {
    method: "DELETE",
    headers: reactorHeaders(apiKey),
  });
  return res.ok;
}
