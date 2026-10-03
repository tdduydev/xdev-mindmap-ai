import Testing
@testable import MindMapAILocal

@Suite struct LocalDeviceEligibilityTests {
    static let gib: UInt64 = 1 << 30

    /// ADR 0011, decision 1: iPhone 15 and later by identifier, never by chip.
    @Test(arguments: [
        ("iPhone14,7", false), // iPhone 14
        ("iPhone15,2", false), // iPhone 14 Pro, A16 like iPhone 15
        ("iPhone15,3", false), // iPhone 14 Pro Max
        ("iPhone15,4", true),  // iPhone 15
        ("iPhone15,5", true),  // iPhone 15 Plus
        ("iPhone16,1", true),  // iPhone 15 Pro
        ("iPhone17,3", true),  // iPhone 16
        ("iPhone18,2", true),  // iPhone 17 Pro Max
        ("iPhone", false),
        ("iPhone15", false),
        ("iPod9,1", false),
    ])
    func iPhones(identifier: String, eligible: Bool) {
        #expect(LocalDeviceEligibility.isEligible(modelIdentifier: identifier, physicalMemory: 6 * Self.gib, isAppleSilicon: true) == eligible)
    }

    @Test(arguments: [
        ("iPad16,3", UInt64(8), true),
        ("iPad14,1", UInt64(4), false),
        ("Mac14,2", UInt64(8), true),
        ("Mac14,2", UInt64(16), true),
        ("MacBookAir10,1", UInt64(7), false),
    ])
    func iPadsAndMacsNeedEightGigabytes(identifier: String, gigabytes: UInt64, eligible: Bool) {
        // 7.5 GiB is how much an 8 GB device reports, not a full 8.
        let reported = gigabytes * Self.gib * 15 / 16
        #expect(LocalDeviceEligibility.isEligible(modelIdentifier: identifier, physicalMemory: reported, isAppleSilicon: true) == eligible)
    }

    @Test func intelIsNeverEligible() {
        #expect(!LocalDeviceEligibility.isEligible(modelIdentifier: "MacPro7,1", physicalMemory: 64 * Self.gib, isAppleSilicon: false))
    }

    @Test func eightGigabytesGetTheLargerModel() {
        #expect(LocalDeviceEligibility.recommendedModel(physicalMemory: 6 * Self.gib) == .qwen3_1_7B)
        #expect(LocalDeviceEligibility.recommendedModel(physicalMemory: 8 * Self.gib * 15 / 16) == .qwen3_4B)
    }

    @Test func iPhone15FitsTheDefaultModel() {
        // An iPhone 15 reports about 5.6 GiB of its 6 GB.
        let reported = 6 * Self.gib * 15 / 16
        #expect(reported >= LocalModel.qwen3_1_7B.minimumPhysicalMemory)
        #expect(reported < LocalModel.qwen3_4B.minimumPhysicalMemory)
    }
}
