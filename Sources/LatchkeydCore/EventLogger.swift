import Foundation

public struct EventLogger {
    public let eventsURL: URL

    public init(eventsURL: URL) {
        self.eventsURL = eventsURL
    }

    public func log(
        command: String,
        result: String,
        reason: String? = nil,
        backendType: BackendType? = nil,
        wrapperName: String? = nil,
        wrapperPath: String? = nil,
        binaryName: String? = nil,
        binaryPath: String? = nil
    ) {
        do {
            try FileManager.default.createDirectory(at: eventsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: eventsURL.path) {
                FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
            }

            let event = EventRecord(
                timestamp: isoTimestamp(),
                command: command,
                result: result,
                reason: reason,
                backendType: backendType?.rawValue,
                wrapperName: wrapperName,
                wrapperPath: wrapperPath,
                binaryName: binaryName,
                binaryPath: binaryPath
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let line = try encoder.encode(event) + Data("\n".utf8)
            let handle = try FileHandle(forWritingTo: eventsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } catch {
            // Event logging is best effort in V1.
        }
    }
}
