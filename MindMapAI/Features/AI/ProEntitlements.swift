/// The AI features the Pro unlock covers (FR-STO-01, docs/pricing.md). The rest
/// of AI stays free.
enum ProFeature: Hashable, CaseIterable {
    /// Generating a map from a description longer than `AIRequestDefaults.longDescriptionLength`.
    case longMapDescription
    /// Summarizing from the central topic, which covers the whole map.
    case wholeMapSummary
    case missingTopics
}

/// Answers whether a Pro feature is unlocked. The AI code asks here, so the
/// StoreKit entitlements of MM-13 plug in without touching it.
protocol ProEntitlements {
    func isUnlocked(_ feature: ProFeature) -> Bool
}

/// Everything unlocked, until purchases exist (MM-13).
struct AllFeaturesUnlocked: ProEntitlements {
    func isUnlocked(_ feature: ProFeature) -> Bool { true }
}
