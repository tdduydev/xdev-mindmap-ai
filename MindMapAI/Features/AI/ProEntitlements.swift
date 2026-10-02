/// The features the Pro unlock covers (FR-STO-01, docs/pricing.md). The rest
/// of AI and export stays free.
enum ProFeature: Hashable, CaseIterable {
    /// Generating a map from a description longer than `AIRequestDefaults.longDescriptionLength`.
    case longMapDescription
    /// Summarizing from the central topic, which covers the whole map.
    case wholeMapSummary
    case missingTopics
    /// PNG export above 1×.
    case highResolutionImage
    /// PDF export over several pages at actual size; one fitted page is free.
    case multiPagePDF
}

/// Answers whether a Pro feature is unlocked. AI and export ask here, so the
/// StoreKit entitlements of MM-13 plug in without touching it.
protocol ProEntitlements {
    func isUnlocked(_ feature: ProFeature) -> Bool
}

/// Everything unlocked, until purchases exist (MM-13).
struct AllFeaturesUnlocked: ProEntitlements {
    func isUnlocked(_ feature: ProFeature) -> Bool { true }
}
