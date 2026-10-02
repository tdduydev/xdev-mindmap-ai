import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SystemImageClipboard {
    static var hasImage: Bool {
        #if os(macOS)
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
        #else
        UIPasteboard.general.hasImages
        #endif
    }

    static var imageData: Data? {
        #if os(macOS)
        let board = NSPasteboard.general
        for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier] {
            if let data = board.data(forType: NSPasteboard.PasteboardType(type)) { return data }
        }
        return (board.readObjects(forClasses: [NSImage.self])?.first as? NSImage)?.tiffRepresentation
        #else
        return UIPasteboard.general.image?.pngData()
        #endif
    }
}
