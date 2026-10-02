@testable import MindMapAI
import MindMapAIApple
import MindMapAICore
import Testing

/// The service the app actually ships with, not the mock the assistant tests
/// use: whether AI shows depends on its default provider (MM-21).
@Suite("AI service")
struct AIServiceTests {
    @Test func theAppAsksTheOnDeviceModel() {
        let service = AIService(entitlements: NothingUnlocked())
        #expect(service.provider is AppleFoundationModelProvider)
        #expect(!service.showsEntryPoints, "hidden until the first check, so AI never flashes on an Intel Mac")
    }

    @Test func anIntelBuildHidesEveryAIEntryPoint() async {
        let service = AIService(entitlements: NothingUnlocked())
        await service.refresh()
        #if arch(x86_64)
        // Runs under Rosetta (scripts/rosetta-tests.sh), the closest an Apple
        // silicon Mac gets to an Intel one.
        #expect(service.modelState == .deviceNotEligible)
        #expect(!service.showsEntryPoints)
        #else
        // Apple silicon: whatever the framework says, the service has asked.
        #expect(service.capabilities != nil)
        #endif
    }

    @Test func thePaywallDropsAIToolsWithoutTheModel() {
        let withoutAI = ProFeature.offered(includingAI: false)
        #expect(!withoutAI.isEmpty)
        #expect(withoutAI.allSatisfy { !$0.needsOnDeviceModel })
        #expect(withoutAI.contains(.voiceInput), "voice input uses Speech, not the language model")
        #expect(ProFeature.offered(includingAI: true) == ProFeature.allCases)
    }
}

private struct NothingUnlocked: ProEntitlements {
    func allows(_ feature: ProFeature) -> Bool { false }
}
