// Keeps page flows on one Orbis session from overlapping. A page turn or revision during
// the ~1.6 s prepare used to start a second prepare on the same session, and the two
// flows' waiters resolved each other's events. Each flow now carries a generation number:
// the newest wins, older flows stop at their next step, and the first frame is reported
// with its generation so a stale frame can't mark the wrong page live.

/** The first page after connect can wait on the model to warm up; later pages shouldn't. */
const FIRST_CONDITIONS_READY_TIMEOUT_MS = 300_000;
const LATER_CONDITIONS_READY_TIMEOUT_MS = 20_000;

export function conditionsReadyTimeoutMs(options: { firstPageOnSession: boolean }): number {
  return options.firstPageOnSession ? FIRST_CONDITIONS_READY_TIMEOUT_MS : LATER_CONDITIONS_READY_TIMEOUT_MS;
}

/** A page flow a newer one replaced. Swift matches the "superseded" in the message. */
export class SupersededError extends Error {
  readonly generation: number;

  constructor(generation: number) {
    super(`superseded: page flow ${generation} replaced by a newer one`);
    this.name = "SupersededError";
    this.generation = generation;
  }
}

export function isSuperseded(error: unknown): boolean {
  if (error instanceof SupersededError) return true;
  return error instanceof Error && error.message.startsWith("superseded:");
}

type Guard = () => void;

/**
 * Runs one page flow at a time, newest first. `claim` starts a flow (prepare) and tells
 * the older one to stop; `follow` continues the newest flow (start). A task gets a
 * `guard` to call after each await, which throws once a newer flow has claimed.
 */
export class GenerationGate {
  private newest = 0;
  private tail: Promise<void> = Promise.resolve();
  private readonly onSuperseded: (error: SupersededError) => void;

  constructor(onSuperseded: (error: SupersededError) => void) {
    this.onSuperseded = onSuperseded;
  }

  get latest(): number {
    return this.newest;
  }

  next(): number {
    return this.newest + 1;
  }

  isCurrent(generation: number): boolean {
    return generation === this.newest;
  }

  claim<T>(generation: number, task: (guard: Guard) => Promise<T>): Promise<T> {
    if (generation <= this.newest) return Promise.reject(new SupersededError(generation));
    const older = this.newest;
    this.newest = generation;
    if (older > 0) this.onSuperseded(new SupersededError(older));
    return this.enqueue(generation, task);
  }

  follow<T>(generation: number, task: (guard: Guard) => Promise<T>): Promise<T> {
    if (!this.isCurrent(generation)) return Promise.reject(new SupersededError(generation));
    return this.enqueue(generation, task);
  }

  private enqueue<T>(generation: number, task: (guard: Guard) => Promise<T>): Promise<T> {
    const guard: Guard = () => {
      if (!this.isCurrent(generation)) throw new SupersededError(generation);
    };
    const run = this.tail.then(() => {
      guard();
      return task(guard);
    });
    this.tail = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
}

/**
 * Decides which video frame is a generation's first. Frames count only after that
 * generation's `generation_started`, so a leftover frame from the previous page can't
 * hand the still over to the wrong picture.
 */
export class FirstFrameWatch {
  private armed: number | null = null;
  private started = false;

  get isWatching(): boolean {
    return this.armed !== null;
  }

  arm(generation: number): void {
    this.armed = generation;
    this.started = false;
  }

  cancel(): void {
    this.armed = null;
    this.started = false;
  }

  generationStarted(): void {
    if (this.armed !== null) this.started = true;
  }

  /** A frame was shown: the generation whose first frame it is, or null. */
  onFrame(): number | null {
    if (this.armed === null || !this.started) return null;
    const generation = this.armed;
    this.cancel();
    return generation;
  }
}
