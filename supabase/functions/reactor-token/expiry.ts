// `reactor-token` mint's `expiresAt`: Unix seconds (docs/CONTRACTS.md §3), which is
// what the app decodes. It used to be milliseconds.

export function tokenExpiresAt(nowMs: number, ttlSeconds: number): number {
  return Math.floor(nowMs / 1000) + ttlSeconds;
}
