import CryptoKit
import Foundation

public enum LatchkeydError: Error {
    case usage(String)
    case io(String)
    case manifest(String)
    case trust(String, [String: JSONValue]?)
    case backend(String)
    case logging(String, [String: JSONValue]?)
    case execution(String, Int32?)

    public var exitCode: Int32 {
        switch self {
        case .usage:
            return 2
        case .io:
            return 3
        case .manifest:
            return 4
        case .trust:
            return 5
        case .backend:
            return 6
        case .logging:
            return 8
        case .execution(_, let status):
            return status ?? 7
        }
    }

    public var errorOutput: ErrorOutput {
        switch self {
        case .usage(let message):
            return ErrorOutput(code: "USAGE_ERROR", message: message)
        case .io(let message):
            return ErrorOutput(code: "IO_ERROR", message: message)
        case .manifest(let message):
            return ErrorOutput(code: "MANIFEST_INVALID", message: message)
        case .trust(let message, let details):
            return ErrorOutput(code: "TRUST_DENIED", message: message, details: details)
        case .backend(let message):
            return ErrorOutput(code: "BACKEND_ERROR", message: message)
        case .logging(let message, let details):
            return ErrorOutput(code: "LOGGING_ERROR", message: message, details: details)
        case .execution(let message, let status):
            var details: [String: JSONValue] = [:]
            if let status {
                details["exitStatus"] = .int(Int(status))
            }
            return ErrorOutput(code: "EXEC_FAILED", message: message, details: details.isEmpty ? nil : details)
        }
    }
}

extension LatchkeydError {
    var logShape: (result: String, reason: String) {
        switch self {
        case .usage:
            return ("denied", "usage_error")
        case .io:
            return ("failed", "io_error")
        case .manifest:
            return ("denied", "manifest_invalid")
        case .trust:
            return ("denied", "trust_denied")
        case .backend:
            return ("denied", "backend_error")
        case .logging:
            return ("failed", "logging_error")
        case .execution:
            return ("failed", "exec_failed")
        }
    }
}

public enum PathKind {
    case wrapper
    case binary
}

public struct AppPaths {
    public let supportDirectory: URL
    public let manifestURL: URL
    public let eventsURL: URL

    public static func resolve(fileManager: FileManager = .default) throws -> AppPaths {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("latchkeyd", isDirectory: true)

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        return AppPaths(
            supportDirectory: baseDirectory,
            manifestURL: baseDirectory.appendingPathComponent("manifest.json"),
            eventsURL: baseDirectory.appendingPathComponent("events.jsonl")
        )
    }
}

public func canonicalPath(_ path: String, relativeTo base: URL? = nil) -> String {
    let url: URL
    if path.hasPrefix("/") {
        url = URL(fileURLWithPath: path)
    } else if let base {
        url = base.appendingPathComponent(path)
    } else {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
    }
    return url.standardizedFileURL.resolvingSymlinksInPath().path
}

public func sha256(forFileAtPath path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

public func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(value)
}

public func writeJSON<T: Encodable>(_ value: T, to handle: FileHandle) throws {
    try handle.write(contentsOf: encodeJSON(value))
    try handle.write(contentsOf: Data("\n".utf8))
}

public func decodeManifest(from url: URL) throws -> Manifest {
    let decoder = JSONDecoder()
    do {
        return try decoder.decode(Manifest.self, from: Data(contentsOf: url))
    } catch {
        throw LatchkeydError.manifest("Failed to decode manifest at \(url.path): \(error.localizedDescription)")
    }
}

public func encodeManifest(_ manifest: Manifest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(manifest)
}

public func writeManifest(_ manifest: Manifest, to url: URL) throws {
    let data = try encodeManifest(manifest)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

public func resolveExecutable(named name: String, environment: [String: String]) -> String? {
    if name.contains("/") {
        return canonicalPath(name)
    }

    let pathValue = environment["PATH"] ?? ""
    for entry in pathValue.split(separator: ":").map(String.init).filter({ !$0.isEmpty }) {
        let candidate = URL(fileURLWithPath: entry).appendingPathComponent(name).path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return canonicalPath(candidate)
        }
    }
    return nil
}

public func fileExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

public func maskValue(_ value: String) -> String {
    guard value.count > 4 else { return String(repeating: "*", count: value.count) }
    let start = value.prefix(2)
    let end = value.suffix(2)
    return "\(start)***\(end)"
}

public func isoTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

public func currentProcessCommandLine(parentPID: Int32? = nil) -> String {
    let pid = parentPID ?? getppid()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "command="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    } catch {
        return ""
    }
}
