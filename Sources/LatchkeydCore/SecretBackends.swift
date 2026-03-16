import Foundation

public protocol SecretBackend {
    var type: BackendType { get }
    func availabilityCheck() throws
    func resolveSecret(spec: SecretSpec) throws -> String
}

public struct SecretBackendFactory {
    public static func makeBackend(config: SecretBackendConfig) throws -> SecretBackend {
        switch config.type {
        case .file:
            guard let filePath = config.filePath else {
                throw LatchkeydError.backend("File backend requires `backend.filePath` in the manifest.")
            }
            return FileSecretBackend(filePath: canonicalPath(filePath))
        case .keychain:
            return KeychainSecretBackend(servicePrefix: config.servicePrefix ?? "latchkeyd", account: config.account ?? NSUserName())
        }
    }
}

public struct FileSecretBackend: SecretBackend {
    public let type: BackendType = .file
    private let filePath: String

    public init(filePath: String) {
        self.filePath = filePath
    }

    public func availabilityCheck() throws {
        guard fileExists(filePath) else {
            throw LatchkeydError.backend("File backend secret store not found at \(filePath).")
        }
    }

    public func resolveSecret(spec: SecretSpec) throws -> String {
        try availabilityCheck()
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let store = try JSONDecoder().decode([String: String].self, from: data)
        guard let value = store[spec.backendKey] else {
            throw LatchkeydError.backend("File backend key `\(spec.backendKey)` is missing from \(filePath).")
        }
        return value
    }
}

public struct KeychainSecretBackend: SecretBackend {
    public let type: BackendType = .keychain
    private let servicePrefix: String
    private let account: String

    public init(servicePrefix: String, account: String) {
        self.servicePrefix = servicePrefix
        self.account = account
    }

    public func availabilityCheck() throws {
        guard fileExists("/usr/bin/security") else {
            throw LatchkeydError.backend("macOS security CLI not found at /usr/bin/security.")
        }
    }

    public func resolveSecret(spec: SecretSpec) throws -> String {
        try availabilityCheck()
        let service = "\(servicePrefix)/\(spec.backendKey)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", account, "-s", service, "-w"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown keychain failure."
            throw LatchkeydError.backend("Keychain lookup failed for service `\(service)`: \(errorMessage)")
        }

        let value = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            throw LatchkeydError.backend("Keychain returned an empty value for service `\(service)`.")
        }
        return value
    }
}
