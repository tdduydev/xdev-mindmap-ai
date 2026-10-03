import Darwin
import Foundation

// Shared by both spike binaries. sun_path holds 104 bytes on macOS, so the
// socket name stays short: the group container path already uses ~70.
enum SpikeSocket {
    static func groupContainer() -> URL? {
        let group = ProcessInfo.processInfo.environment["SPIKE_GROUP"] ?? "M6C7NX9MUZ.asia.xdev.mindmapai"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    static func errno_() -> String { String(cString: strerror(errno)) + " (\(errno))" }

    static func log(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Reads newline-delimited messages from a descriptor.
struct LineReader {
    let fd: Int32
    var buffer = [UInt8]()

    mutating func next() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[..<n])
        }
    }
}

func writeAll(_ fd: Int32, _ text: String) -> Bool {
    var bytes = Array((text + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
        let n = bytes[offset...].withUnsafeMutableBufferPointer { write(fd, $0.baseAddress, $0.count) }
        if n <= 0 { return false }
        offset += n
    }
    return true
}
