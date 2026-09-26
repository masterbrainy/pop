// CORS for the Pop! functions. The iOS app doesn't need it, but the web
// live-scene bridge and manual/Studio testing do.

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-pop-admin",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Returns a preflight response for OPTIONS requests, else null. */
export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  return null;
}
