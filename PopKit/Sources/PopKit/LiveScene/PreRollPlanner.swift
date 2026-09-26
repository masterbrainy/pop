/// Record, then loop, then pre-animate the page behind, on ONE Orbis session.
///
/// The page on screen animates live until its recorded clip is baked into a loop; then it
/// hands over to the loop and the session, now free, pre-animates the page behind while
/// hidden. At the fold, the page behind is either still live (its video is revealed) or
/// already has its loop (it plays, and the page after it is pre-animated next).
///
/// A pure reducer: given the two pages and what the session is doing, it says what the
/// session should do and what the art page shows. `LivePageController` performs the actions.
public enum PreRollPlanner {
    /// One version of a page, as far as the session is concerned.
    public struct Page: Equatable, Sendable {
        public let key: PageKey
        /// It has a still and a motion prompt, so it can be animated.
        public let canAnimate: Bool
        /// Its loop is attached (and, for the page on screen, ready to play).
        public let hasClip: Bool
        /// A flagged frame keeps it on its still for good.
        public let isHeld: Bool
        /// Its flow already ran without giving a loop (no first frame, or a clip that couldn't
        /// be checked); it's animated again only when it's next shown.
        public let isSpent: Bool

        public init(key: PageKey, canAnimate: Bool, hasClip: Bool, isHeld: Bool, isSpent: Bool) {
            self.key = key
            self.canAnimate = canAnimate
            self.hasClip = hasClip
            self.isHeld = isHeld
            self.isSpent = isSpent
        }
    }

    /// The page flow the session is running now.
    public struct Slot: Equatable, Sendable {
        public let key: PageKey
        /// Started (and still) hidden: its video isn't shown even once it has frames.
        public let isHidden: Bool
        /// Its first frame arrived.
        public let hasFirstFrame: Bool

        public init(key: PageKey, isHidden: Bool, hasFirstFrame: Bool) {
            self.key = key
            self.isHidden = isHidden
            self.hasFirstFrame = hasFirstFrame
        }
    }

    /// The page the session should be animating, and whether it's hidden.
    public struct Target: Equatable, Sendable {
        public let key: PageKey
        public let hidden: Bool

        public init(key: PageKey, hidden: Bool) {
            self.key = key
            self.hidden = hidden
        }
    }

    /// What the art page on screen shows.
    public enum Display: Equatable, Sendable {
        /// The still (drifting), until something moves.
        case still
        /// The live Orbis video of this page.
        case live
        /// This page's baked loop.
        case clip
    }

    public enum Action: Equatable, Sendable {
        /// Start a flow for this page (superseding whatever runs now).
        case animate(PageKey, hidden: Bool)
        /// The hidden flow's page is now on screen: show its video.
        case reveal(PageKey)
        /// Nothing needs the session: stop the flow and keep the connection.
        case idle
    }

    public struct Plan: Equatable, Sendable {
        public let target: Target?
        public let display: Display
        public let actions: [Action]
    }

    public static func plan(onScreen: Page?, behind: Page?, slot: Slot?) -> Plan {
        let target = target(onScreen: onScreen, behind: behind)
        return Plan(target: target, display: display(onScreen: onScreen, slot: slot), actions: actions(target: target, slot: slot))
    }

    /// The page on screen comes first until it has its loop (or can't animate); then the page behind.
    static func target(onScreen: Page?, behind: Page?) -> Target? {
        guard let onScreen else { return nil }
        if onScreen.isHeld || onScreen.hasClip || onScreen.isSpent {
            return preRoll(behind)
        }
        return onScreen.canAnimate ? Target(key: onScreen.key, hidden: false) : nil
    }

    private static func preRoll(_ behind: Page?) -> Target? {
        guard let behind, behind.canAnimate, !behind.hasClip, !behind.isHeld, !behind.isSpent else { return nil }
        return Target(key: behind.key, hidden: true)
    }

    static func display(onScreen: Page?, slot: Slot?) -> Display {
        guard let onScreen, !onScreen.isHeld else { return .still }
        if onScreen.hasClip { return .clip }
        if let slot, slot.key == onScreen.key, slot.hasFirstFrame, !slot.isHidden { return .live }
        return .still
    }

    static func actions(target: Target?, slot: Slot?) -> [Action] {
        guard target?.key == slot?.key else {
            if let target { return [.animate(target.key, hidden: target.hidden)] }
            return [.idle]
        }
        if let target, let slot, slot.isHidden, !target.hidden { return [.reveal(slot.key)] }
        return []
    }
}
