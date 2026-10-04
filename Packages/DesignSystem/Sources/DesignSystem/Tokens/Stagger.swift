import Foundation

/// Delays for groups of elements that enter together. Staggering is for
/// infrequent entrances only; routine interactions never stagger.
public nonisolated enum Stagger {
    /// Seconds between neighbouring items.
    public static let perItem: TimeInterval = 0.04
    /// Items past this many arrive with the last staggered one, so a long list
    /// never keeps the user waiting.
    public static let cap = 8
    /// Seconds between semantic groups of an onboarding card.
    public static let perOnboardingGroup: TimeInterval = 0.10

    /// The entrance delay for the item at `index`. Linear to the cap, flat after it.
    public static func delay(forIndex index: Int, reduceMotion: Bool = false) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        return perItem * Double(min(max(index, 0), cap - 1))
    }

    /// The entrance delay for an onboarding card's group of content.
    public static func delay(forOnboardingGroup group: Int, reduceMotion: Bool = false) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        return perOnboardingGroup * Double(max(group, 0))
    }
}
