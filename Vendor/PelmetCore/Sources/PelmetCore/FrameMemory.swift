// FrameMemory.swift
// The last in-slot frame per icon, kept across conceals so the Apply count
// and the settle can place a concealed icon without a reveal (AppState's,
// read through `ApplyPass.rememberedFrames`). Pure: the app hands it each
// walk and each pass.

import CoreGraphics
import Foundation

public struct FrameMemory: Equatable, Sendable {
    /// Last primary-band frame per canonical key, read in its slot.
    public private(set) var frames: [ItemID: CGRect] = [:]
    /// The chevron's midX when each frame was remembered: concealed icons
    /// sit left of the chevron and slide with it, so a frame remembered
    /// before Apply moved an icon out of Hidden (chevron 1523 → 1451,
    /// 2026-09-20 21:39) reads right of the new chevron and lit the button
    /// again for nothing. The count shifts each frame by the chevron delta.
    public private(set) var chevronMidX: [ItemID: CGFloat] = [:]
    /// Icons whose frame a pass's drags made stale: only a walk at rest
    /// frames them again.
    public private(set) var awaitingRest: Set<ItemID> = []

    public init() {}

    /// One walk's frames for the icons it read in their slot (primary band,
    /// neither concealed nor out on their own).
    public mutating func remember(_ inSlot: [ItemID: CGRect], chevronMidX chevron: CGFloat?, atRest: Bool) {
        for (key, frame) in inSlot {
            if awaitingRest.contains(key) {
                guard atRest else { continue }
                awaitingRest.remove(key)
            }
            frames[key] = frame
            chevronMidX[key] = chevron
        }
    }

    /// A pass dragged icons where concealed ones sit, and `read` is what the
    /// walk after its last drag placed. Every other frame is from the bar
    /// before the drags: a drag shifts the icons beside it and nothing
    /// re-reads one hidden through it, nor does the chevron shift account
    /// for it. Sound kept a frame from before Snib's drag moved it, the
    /// collapsed bar read it in place, and a real reorder in a concealed
    /// Hidden read as no move (live test, 2026-10-13); with every icon framed
    /// the settle would have cleared it. Forgotten, the icon is one the bar
    /// cannot place until its section is out again: its edit stays pending,
    /// never dark.
    @discardableResult
    public mutating func forget(allBut read: Set<ItemID>) -> Set<ItemID> {
        let stale = Set(frames.keys).subtracting(read)
        for key in stale {
            frames.removeValue(forKey: key)
            chevronMidX.removeValue(forKey: key)
        }
        awaitingRest.formUnion(stale)
        return stale
    }
}
