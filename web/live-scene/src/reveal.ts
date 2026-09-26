// Decides whether a page flow's video is shown. The app pre-animates the next page behind
// the one on screen: that flow runs hidden (reveal:false), records its clip, and its video
// only appears if the parent folds to that page while it is still live. The reveal can come
// before or after the first frame, so both are remembered here, for the newest flow only.

export type RevealResult = { revealed: boolean; hasFirstFrame: boolean };

type Slot = {
  generation: number;
  /** What prepare or start asked for. */
  requested: boolean;
  /** Set by reveal(); once shown, a page is not hidden again. */
  revealed: boolean;
  firstFrame: boolean;
};

const REFUSED: RevealResult = { revealed: false, hasFirstFrame: false };

export class RevealState {
  private slot: Slot | null = null;

  /** Records whether `generation` should show its video (prepare, or start overriding it). */
  request(generation: number, reveal: boolean): void {
    this.slotFor(generation).requested = reveal;
  }

  isShown(generation: number): boolean {
    const slot = this.slot;
    if (!slot || slot.generation !== generation) return true;
    return slot.requested || slot.revealed;
  }

  /** `generation`'s first frame arrived; `background` means its video stays hidden. */
  firstFrame(generation: number): { background: boolean } {
    this.slotFor(generation).firstFrame = true;
    return { background: !this.isShown(generation) };
  }

  /**
   * Shows `generation` if it is still the newest flow (`latest`). `hasFirstFrame` tells the
   * caller the video is already playing and should appear now; otherwise the first frame will.
   */
  reveal(generation: number, latest: number): RevealResult {
    if (latest <= 0 || generation !== latest) return REFUSED;
    const slot = this.slotFor(generation);
    slot.revealed = true;
    return { revealed: true, hasFirstFrame: slot.firstFrame };
  }

  clear(): void {
    this.slot = null;
  }

  /** The slot for `generation`; a newer generation replaces the older one's. */
  private slotFor(generation: number): Slot {
    if (this.slot?.generation !== generation) {
      this.slot = { generation, requested: true, revealed: false, firstFrame: false };
    }
    return this.slot;
  }
}
