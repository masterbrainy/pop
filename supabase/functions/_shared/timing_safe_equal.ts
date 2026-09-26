// A constant-time string comparison for checking the `x-pop-admin` header
// against REACTOR_ADMIN_SECRET without leaking timing information about how
// much of the secret matched.

export function timingSafeEqualStrings(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  const length = Math.max(aBytes.length, bBytes.length, 1);

  // Always run the same number of iterations regardless of where (or
  // whether) the two strings first differ, and fold the length difference in
  // up front so a length mismatch alone can't short-circuit the loop.
  let diff = aBytes.length ^ bBytes.length;
  for (let i = 0; i < length; i++) {
    const x = i < aBytes.length ? aBytes[i] : 0;
    const y = i < bBytes.length ? bBytes[i] : 0;
    diff |= x ^ y;
  }
  return diff === 0;
}
