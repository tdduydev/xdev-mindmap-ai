/// What the AI code needs from the Pro unlock, so its tests can lock or unlock
/// features without a StoreKit session. `ProEntitlement` is the app's answer.
protocol ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool
}

extension ProEntitlement: ProEntitlements {}
