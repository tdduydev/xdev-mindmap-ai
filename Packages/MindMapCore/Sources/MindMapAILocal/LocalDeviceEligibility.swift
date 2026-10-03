import Foundation

/// Which devices may run a local model (ADR 0011, decision 1). Pure, so the
/// rules are tested from a table; `current` reads the real device.
public enum LocalDeviceEligibility {
    /// iPhone: iPhone 15 and 15 Plus (`iPhone15,4`, `iPhone15,5`) and every
    /// `iPhone16,*` or newer, decided by model identifier rather than chip,
    /// since iPhone 14 Pro (`iPhone15,2`, `iPhone15,3`) has the same A16.
    /// iPad and Mac: Apple silicon with at least 8 GB [Đề xuất]. Anything else,
    /// the Simulator included, is not eligible.
    public static func isEligible(modelIdentifier: String, physicalMemory: UInt64, isAppleSilicon: Bool) -> Bool {
        guard isAppleSilicon else { return false }
        if let (major, minor) = version(of: modelIdentifier, prefix: "iPhone") {
            return major > 15 || (major == 15 && (minor == 4 || minor == 5))
        }
        if modelIdentifier.hasPrefix("iPad") || modelIdentifier.hasPrefix("Mac") {
            return hasAtLeast(8, physicalMemory)
        }
        return false
    }

    /// The model the device should run: the 4B one from 8 GB, else the default.
    public static func recommendedModel(physicalMemory: UInt64) -> LocalModel {
        hasAtLeast(8, physicalMemory) ? .qwen3_4B : .qwen3_1_7B
    }

    /// Whether `memory` is a device sold with `gigabytes`: the system reports
    /// a little less than the nominal amount, so allow 10 %.
    static func hasAtLeast(_ gigabytes: UInt64, _ memory: UInt64) -> Bool {
        memory >= gigabytes * LocalModel.gibibyte * 9 / 10
    }

    /// "iPhone15,4" → (15, 4).
    static func version(of identifier: String, prefix: String) -> (Int, Int)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let parts = identifier.dropFirst(prefix.count).split(separator: ",")
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    /// This device. The Simulator reports the Mac's identifier through
    /// `hw.machine`, so it is ruled out explicitly: MLX needs a real GPU.
    public static var current: Bool {
        #if targetEnvironment(simulator) || arch(x86_64)
        return false
        #else
        return isEligible(
            modelIdentifier: currentModelIdentifier,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            isAppleSilicon: true
        )
        #endif
    }

    /// "iPhone16,1" or "iPad14,1" from `hw.machine`; a Mac answers "arm64"
    /// there and its "Mac14,3" in `hw.model`. Asked in that order rather than
    /// by platform, so the core does not branch on the OS.
    static var currentModelIdentifier: String {
        let machine = sysctlString("hw.machine")
        if machine.hasPrefix("iPhone") || machine.hasPrefix("iPad") { return machine }
        return sysctlString("hw.model")
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}
