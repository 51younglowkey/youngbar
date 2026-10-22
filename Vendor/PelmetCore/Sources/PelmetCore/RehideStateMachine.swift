// RehideStateMachine.swift
// Pure reveal/rehide state machine. All timing is injected (deadlines are
// data, not timers), so every transition is unit-testable and the engine can
// never be toggled mid-flight: callers apply the returned effect, and only
// report completion back via `.transitionSettled`.

import Foundation

public enum RevealReason: Hashable, Sendable {
    case hover
    /// Pointer is on a display configured "always show everything".
    case displayPolicy
    case click
    case doubleClick
    case hotkey
    case statusItem
    case settingsPreview
    /// The user started a ⌘-drag in the bar: the hidden run is only a drop
    /// target while it is on screen.
    case barDrag
    /// The user asked to see one item in the real bar: Show in Menu Bar, a
    /// press on one of Pelmet's own extras, ⌘↩ in Search. A panel can't show
    /// that, so routing always picks the bar. The machine treats it like
    /// `.hotkey`: the pointer never entered the bar either.
    ///
    /// Asked with NO sections, it is an item that comes out on its own: the
    /// machine then reads `.revealed(sections: [], .itemInBar)`, which owns
    /// when the icon goes back (countdown, pointer, click elsewhere) while the
    /// bar stays collapsed as far as every section is concerned.
    case itemInBar
}

public enum RehideTrigger: Hashable, Sendable {
    case delayExpired
    case clickedElsewhere
    case pointerLeftBand
}

public struct RehidePolicy: Equatable, Sendable {
    public var autoRehide: Bool
    public var delay: TimeInterval
    public var rehideOnClickElsewhere: Bool

    public init(autoRehide: Bool = true, delay: TimeInterval = 5, rehideOnClickElsewhere: Bool = true) {
        self.autoRehide = autoRehide
        self.delay = delay
        self.rehideOnClickElsewhere = rehideOnClickElsewhere
    }
}

/// What the caller must do after feeding an event in.
public enum RehideEffect: Equatable, Sendable {
    case none
    /// Ask the engine to reveal these sections. Report back with `.transitionSettled`.
    case reveal(Set<Section>)
    /// Ask the engine to conceal everything non-visible. Report back with `.transitionSettled`.
    case conceal
    /// Ask the engine to take back every section but these, which stay out.
    /// Report back with `.transitionSettled`.
    case narrow(Set<Section>)
    /// (Re)arm the rehide timer for this deadline.
    case armTimer(Date)
    case cancelTimer
}

public enum RehideEvent: Equatable, Sendable {
    case revealRequested(Set<Section>, RevealReason)
    case concealRequested
    case toggleRequested(Set<Section>, RevealReason)
    case trigger(RehideTrigger)
    /// The engine finished applying the last reveal/conceal.
    case transitionSettled
    /// The pointer re-entered the menubar band (pauses pending rehide).
    case pointerReturned
    /// The pointer left the band: (re)arm the rehide countdown — never an
    /// immediate conceal, the user may be heading to a popover.
    case pointerLeft
    /// The presenter put these sections away on its own (the panel folding
    /// Always Hidden): nothing moves, the machine stops counting them as
    /// out, so a later ask for them widens again.
    case sectionsPutAway(Set<Section>)
    /// An icons-only reveal found every icon already let go (its app quit
    /// while the reveal waited behind a conceal): nothing came out.
    case nothingCameOut
    /// Keep only these sections out, for this reason (an Apply pass over
    /// on a display set to always show: Always Hidden goes back, Hidden
    /// stays). Acts on a settled reveal wider than `sections` only.
    case narrowRequested(Set<Section>, RevealReason)
}

public struct RehideStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case concealed
        /// Engine is applying a transition; queued intent (if any) runs after settle.
        case transitioning(target: Target, queued: Target?)
        case revealed(sections: Set<Section>, reason: RevealReason)

        public enum Target: Equatable, Sendable {
            case reveal(Set<Section>, RevealReason)
            case conceal
        }
    }

    public private(set) var state: State = .concealed
    public var policy: RehidePolicy

    public init(policy: RehidePolicy = RehidePolicy()) {
        self.policy = policy
    }

    public mutating func handle(_ event: RehideEvent, now: Date = Date()) -> [RehideEffect] {
        switch (state, event) {
        // ── Reveal ───────────────────────────────────────────────────────────
        case (.concealed, .revealRequested(let sections, let reason)),
             (.concealed, .toggleRequested(let sections, let reason)):
            state = .transitioning(target: .reveal(sections, reason), queued: nil)
            return [.reveal(sections)]

        case (.revealed(let current, _), .revealRequested(_, .hover)) where current.isEmpty:
            // Only single icons are out (Show in Menu Bar): the pointer coming
            // to them is not a request for the section behind them.
            return [.none]

        case (.revealed(let current, _), .revealRequested(let sections, let reason))
            where !sections.subtracting(current).isEmpty:
            // Widen the reveal (e.g. hidden already out, now always-hidden too).
            let union = current.union(sections)
            state = .transitioning(target: .reveal(union, reason), queued: nil)
            return [.cancelTimer, .reveal(union)]

        case (.revealed(let current, let reason), .revealRequested(_, let requested)):
            // Already showing these sections — just refresh the timer. Keep
            // the WIDER tracked set and the original reason: a routine hover
            // re-fire during a full [.hidden, .alwaysHidden] reveal must not
            // narrow tracking (companion applies would hide always-hidden
            // extras still physically on screen) or downgrade a deliberate
            // reveal onto hover's quick rehide clock. The other way round
            // holds: a deliberate request on a hover reveal makes it the
            // click's (a chevron click landing just as the hover opened).
            let kept = (reason == .hover && requested != .hover) ? requested : reason
            state = .revealed(sections: current, reason: kept)
            return armIfNeeded(reason: kept, now: now)

        case (.revealed(let current, _), .toggleRequested(let sections, let reason))
            where current.isEmpty && !sections.isEmpty:
            // Only single icons are out (Show in Menu Bar): the bar reads as
            // collapsed, so the chevron or the hotkey opens the section
            // instead of putting the icons away. They go back with it.
            state = .transitioning(target: .reveal(sections, reason), queued: nil)
            return [.cancelTimer, .reveal(sections)]

        case (.revealed, .toggleRequested):
            state = .transitioning(target: .conceal, queued: nil)
            return [.cancelTimer, .conceal]

        // ── Conceal ──────────────────────────────────────────────────────────
        case (.revealed, .concealRequested):
            state = .transitioning(target: .conceal, queued: nil)
            return [.cancelTimer, .conceal]

        case (.revealed(_, _), .trigger(let trigger)):
            guard shouldRehide(on: trigger) else { return [.none] }
            state = .transitioning(target: .conceal, queued: nil)
            return [.cancelTimer, .conceal]

        // ── Narrow ───────────────────────────────────────────────────────────
        // One swap takes the extra sections back. A conceal with the policy's
        // reveal queued behind it reflowed the bar twice, and reads between
        // the two saw a bar that was neither (live test, 2026-10-13).
        case (.revealed(let current, _), .narrowRequested(let sections, let reason))
            where !sections.isEmpty && sections.isStrictSubset(of: current):
            state = .transitioning(target: .reveal(sections, reason), queued: nil)
            return [.cancelTimer, .narrow(sections)]

        // ── Put away by the presenter ────────────────────────────────────────
        // Never down to no section: that state means icons out on their own.
        case (.revealed(let current, let reason), .sectionsPutAway(let away))
            where !current.isDisjoint(with: away) && !current.subtracting(away).isEmpty:
            state = .revealed(sections: current.subtracting(away), reason: reason)
            return [.none]

        case (.transitioning(target: .reveal(let inFlight, let reason), queued: nil), .sectionsPutAway(let away))
            where !inFlight.isDisjoint(with: away) && !inFlight.subtracting(away).isEmpty:
            state = .transitioning(target: .reveal(inFlight.subtracting(away), reason), queued: nil)
            return [.none]

        case (.transitioning(.reveal(let sections, _), let queued), .nothingCameOut) where sections.isEmpty:
            // Settles as the conceal it amounts to (review APP-6): settled as
            // `.revealed([])`, nothing was out and hover stayed dead.
            state = .transitioning(target: .conceal, queued: queued)
            return handle(.transitionSettled, now: now)

        // ── Mid-flight: queue, never interleave ──────────────────────────────
        case (.transitioning(let target, let queued), .revealRequested(let sections, let reason)):
            // A hover re-fire must not cancel a deliberately queued conceal
            // (chevron click mid-reveal) — that made the click a dead click.
            if queued == .conceal, reason == .hover {
                return [.none]
            }
            // Same for icons Show in Menu Bar is bringing out: a hover merged
            // into that transition would slide the whole section out.
            if reason == .hover, Self.bringsIconsOnly(target: target, queued: queued) {
                return [.none]
            }
            // A reveal landing mid-reveal must never NARROW what's in flight
            // or queued: the engine's reveal is additive, so settling a queued
            // [hidden] right after a double-click [hidden, alwaysHidden]
            // leaves the bar fully revealed while the machine tracks
            // hidden-only — hover reveals then keep showing always-hidden
            // items until the next conceal (observed live 2026-08-31 22:36).
            // Union instead; a request already covered is a no-op, and a
            // hover re-fire never downgrades a deliberate reveal's reason.
            if case .reveal(let inFlight, let inFlightReason) = target {
                var union = inFlight
                var keptReason = inFlightReason
                if case .reveal(let queuedSections, let queuedReason)? = queued {
                    union.formUnion(queuedSections)
                    keptReason = queuedReason
                }
                if sections.subtracting(union).isEmpty {
                    // Covered — but a deliberate request landing on a hover
                    // reveal makes it the click's: the bar then keeps the
                    // click's rehide policy, not the glance's quick one.
                    if reason != .hover, inFlightReason == .hover, queued == nil {
                        state = .transitioning(target: .reveal(inFlight, reason), queued: nil)
                    }
                    return [.none]
                }
                union.formUnion(sections)
                state = .transitioning(
                    target: target,
                    queued: .reveal(union, reason == .hover ? keptReason : reason)
                )
                return [.none]
            }
            state = .transitioning(target: target, queued: .reveal(sections, reason))
            return [.none]

        case (.transitioning(let target, let alreadyQueued), .toggleRequested(let sections, let reason)):
            // A toggle means "the opposite of where we're heading" — clicking
            // the chevron during a hover-triggered reveal must queue a conceal,
            // not reinforce the reveal (which reads as a dead click).
            // Except over icons coming out alone (Show in Menu Bar): no section
            // is on its way, so the toggle opens one, as on a settled bar. A
            // second toggle there heads for that section, so it queues the
            // conceal: two presses cancel out, as on a settled bar.
            let queued: State.Target = {
                if case .reveal(let inFlight, _) = target {
                    guard inFlight.isEmpty && !sections.isEmpty else { return .conceal }
                    if case .reveal(let next, _)? = alreadyQueued, !next.isEmpty { return .conceal }
                    return .reveal(sections, reason)
                }
                return .reveal(sections, reason)
            }()
            state = .transitioning(target: target, queued: queued)
            return [.none]

        case (.transitioning(let target, _), .concealRequested):
            state = .transitioning(target: target, queued: .conceal)
            return [.none]

        case (.transitioning(let target, _), .trigger(let trigger)):
            // Same policy gate as the `.revealed` trigger case — a click
            // elsewhere during a sub-second transition must respect
            // `rehideOnClickElsewhere` too, not sneak past it.
            guard shouldRehide(on: trigger) else { return [.none] }
            state = .transitioning(target: target, queued: .conceal)
            return [.none]

        // ── Settle ───────────────────────────────────────────────────────────
        case (.transitioning(let target, let queued), .transitionSettled):
            switch (target, queued) {
            case (.reveal(let sections, let reason), nil):
                state = .revealed(sections: sections, reason: reason)
                return armIfNeeded(reason: reason, now: now)
            case (.conceal, nil):
                state = .concealed
                return [.none]
            case (_, .reveal(let sections, let reason)):
                state = .transitioning(target: .reveal(sections, reason), queued: nil)
                return [.reveal(sections)]
            case (.reveal, .conceal):
                state = .transitioning(target: .conceal, queued: nil)
                return [.conceal]
            case (.conceal, .conceal):
                state = .concealed
                return [.none]
            }

        // ── Pointer pause/resume ─────────────────────────────────────────────
        case (.revealed, .pointerReturned):
            return [.cancelTimer]

        case (.revealed(_, let reason), .pointerLeft):
            // Hover-out after a hover reveal rehides quickly — the user only
            // glanced. Same for a display-policy reveal once the pointer is
            // back on a collapse display. Deliberate reveals (click, hotkey,
            // chevron) keep the full configured delay.
            guard policy.autoRehide else { return [.none] }
            let quick = reason == .hover || reason == .displayPolicy
            let interval = quick ? min(policy.delay, 1.0) : policy.delay
            return [.armTimer(now.addingTimeInterval(interval))]

        default:
            return [.none]
        }
    }

    /// A transition whose only reveal is icons coming out on their own.
    private static func bringsIconsOnly(target: State.Target, queued: State.Target?) -> Bool {
        switch (target, queued) {
        case (.reveal(let sections, _), nil): sections.isEmpty
        case (.reveal(let sections, _), .reveal(let next, _)?): sections.isEmpty && next.isEmpty
        case (.conceal, .reveal(let next, _)?): next.isEmpty
        default: false
        }
    }

    private func shouldRehide(on trigger: RehideTrigger) -> Bool {
        switch trigger {
        case .delayExpired, .pointerLeftBand:
            return policy.autoRehide
        case .clickedElsewhere:
            return policy.rehideOnClickElsewhere
        }
    }

    /// How long icons shown by Show in Menu Bar wait for the pointer at Instant.
    static let itemInBarReach: TimeInterval = 4

    private func armIfNeeded(reason: RevealReason, now: Date) -> [RehideEffect] {
        guard policy.autoRehide else { return [.none] }
        // "Instant" means "as soon as the pointer leaves the bar". A hotkey
        // reveal's pointer never entered it, so there is nothing to leave:
        // the bar stays up until the pointer visits and leaves, a click
        // elsewhere, or the next press. The 0.75 s floor that replaced the
        // old open-shut flash read as "the first press did nothing" (Gab,
        // 2026-09-15).
        if reason == .hotkey, policy.delay == 0 { return [.none] }
        // Show in Menu Bar is picked on the panel or a menu, not the bar: with
        // nothing armed, a pointer that never went up there left the icons
        // out for good (#26, cpierce). Time to reach them; the pointer on the
        // bar or the item's menu open holds them past it.
        if reason == .itemInBar, policy.delay == 0 { return [.armTimer(now.addingTimeInterval(Self.itemInBarReach))] }
        // Floor the settle-time arm: with the rehide delay dialed to 0, a
        // reveal whose pointer isn't parked in the band concealed within
        // milliseconds of settling — an unreadable open-shut flash. Pointer-
        // driven rehide stays instant via `.pointerLeft`; only the "never
        // entered the band" case gets a minimum readable window.
        return [.armTimer(now.addingTimeInterval(max(policy.delay, 0.75)))]
    }
}
