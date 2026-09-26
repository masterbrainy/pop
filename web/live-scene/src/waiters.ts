import type { OrbisMessage } from "./orbis.ts";

type Pending = {
  readonly match: (message: OrbisMessage) => boolean;
  readonly resolve: (message: OrbisMessage) => void;
  readonly reject: (error: Error) => void;
  readonly timer: ReturnType<typeof setTimeout>;
};

/**
 * Waits for model messages that match a condition (for example
 * `conditions_ready`, or a `state` with `has_image: true`). Commands are
 * asynchronous, so these events, not command replies, are the source of truth.
 */
export class MessageWaiters {
  private pending: readonly Pending[] = [];

  /** Resolves with the first matching message, or rejects after `timeoutMs`. */
  waitFor(match: (message: OrbisMessage) => boolean, timeoutMs: number, label: string): Promise<OrbisMessage> {
    return new Promise<OrbisMessage>((resolve, reject) => {
      const entry: Pending = {
        match,
        resolve,
        reject,
        timer: setTimeout(() => {
          this.remove(entry);
          reject(new Error(`${label} did not arrive within ${Math.round(timeoutMs / 1000)} s`));
        }, timeoutMs),
      };
      this.pending = [...this.pending, entry];
    });
  }

  /** Feeds one incoming message to every waiter; matching waiters resolve and are removed. */
  dispatch(message: OrbisMessage): void {
    const matched = this.pending.filter((entry) => entry.match(message));
    if (matched.length === 0) return;
    this.pending = this.pending.filter((entry) => !matched.includes(entry));
    for (const entry of matched) {
      clearTimeout(entry.timer);
      entry.resolve(message);
    }
  }

  /** Rejects every waiter, for example when the session disconnects. */
  rejectAll(error: Error): void {
    const all = this.pending;
    this.pending = [];
    for (const entry of all) {
      clearTimeout(entry.timer);
      entry.reject(error);
    }
  }

  get count(): number {
    return this.pending.length;
  }

  private remove(entry: Pending): void {
    this.pending = this.pending.filter((candidate) => candidate !== entry);
  }
}
