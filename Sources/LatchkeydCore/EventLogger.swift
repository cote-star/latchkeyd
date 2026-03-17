import Foundation

public struct EventLogger {
    public let eventsURL: URL
    private let fileManager: FileManager
    private let appendLine: @Sendable (URL, Data) throws -> Void

    public init(
        eventsURL: URL,
        fileManager: FileManager = .default,
        appendLine: (@Sendable (URL, Data) throws -> Void)? = nil
    ) {
        self.eventsURL = eventsURL
        self.fileManager = fileManager
        self.appendLine = appendLine ?? EventLogger.appendLine
    }

    public func prepare() throws {
        let directoryURL = eventsURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw loggingError(
                "Audit logging is required but the event log directory could not be prepared.",
                auditStatus: "unavailable",
                underlyingError: error
            )
        }

        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: eventsURL.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            throw loggingError(
                "Audit logging is required but the configured event log path is a directory.",
                auditStatus: "unavailable"
            )
        }

        if !exists, !fileManager.createFile(atPath: eventsURL.path, contents: nil) {
            throw loggingError(
                "Audit logging is required but the event log file could not be created.",
                auditStatus: "unavailable"
            )
        }

        do {
            let handle = try FileHandle(forWritingTo: eventsURL)
            try handle.seekToEnd()
            try handle.close()
        } catch {
            throw loggingError(
                "Audit logging is required but the event log file is not writable.",
                auditStatus: "unavailable",
                underlyingError: error
            )
        }
    }

    public func log(
        command: String,
        result: String,
        reason: String? = nil,
        backendType: BackendType? = nil,
        policyMode: ExecMode? = nil,
        wrapperName: String? = nil,
        wrapperPath: String? = nil,
        binaryName: String? = nil,
        binaryPath: String? = nil,
        sessionId: String? = nil,
        operationName: String? = nil
    ) throws {
        try prepare()

        let event = EventRecord(
            timestamp: isoTimestamp(),
            command: command,
            result: result,
            reason: reason,
            backendType: backendType?.rawValue,
            wrapperName: wrapperName,
            wrapperPath: wrapperPath,
            binaryName: binaryName,
            binaryPath: binaryPath,
            policyMode: policyMode?.rawValue,
            sessionId: sessionId,
            operationName: operationName
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = try encoder.encode(event) + Data("\n".utf8)

        do {
            try appendLine(eventsURL, line)
        } catch {
            throw loggingError(
                "Audit logging failed after command processing began. The run result is incomplete until the log path is fixed.",
                auditStatus: "incomplete",
                underlyingError: error
            )
        }
    }

    private func loggingError(
        _ message: String,
        auditStatus: String,
        underlyingError: Error? = nil
    ) -> LatchkeydError {
        var details: [String: JSONValue] = [
            "eventsPath": .string(eventsURL.path),
            "auditStatus": .string(auditStatus)
        ]
        if let underlyingError {
            details["underlyingError"] = .string(underlyingError.localizedDescription)
        }
        return .logging(message, details)
    }

    static func appendLine(to url: URL, data: Data) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
