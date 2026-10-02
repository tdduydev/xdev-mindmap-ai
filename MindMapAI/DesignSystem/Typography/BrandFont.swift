import CoreText
import Foundation
import OSLog

/// The bundled brand faces (SIL OFL 1.1, licence in `Resources/Fonts/OFL.txt`).
/// The raw value is both the file name and the PostScript name, which is what
/// `Font.custom` looks up.
enum BrandFont: String, CaseIterable, Sendable {
    case beVietnamProRegular = "BeVietnamPro-Regular"
    case beVietnamProMedium = "BeVietnamPro-Medium"
    case beVietnamProSemiBold = "BeVietnamPro-SemiBold"
    case spaceGroteskSemiBold = "SpaceGrotesk-SemiBold"

    var postScriptName: String { rawValue }

    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "ttf") }

    /// Registers every face for this process. Registering in code works the same
    /// on iOS and macOS and needs no Info.plist array, which the generated
    /// Info.plist cannot hold. Call before the first view draws; repeat calls
    /// do nothing.
    static func registerAll() {
        _ = registered
    }

    /// The faces that are available after registration.
    static let registered: Set<BrandFont> = {
        var available = Set<BrandFont>()
        for font in BrandFont.allCases {
            guard let url = font.url else {
                Log.designSystem.error("Brand font missing from the bundle: \(font.rawValue, privacy: .public)")
                continue
            }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || font.isInstalled {
                available.insert(font)
            } else {
                let reason = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "unknown"
                Log.designSystem.error("Brand font failed to register: \(font.rawValue, privacy: .public), \(reason, privacy: .public)")
            }
        }
        return available
    }()

    /// Whether CoreText resolves the PostScript name to this face rather than
    /// a fallback.
    var isInstalled: Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == postScriptName
    }
}
