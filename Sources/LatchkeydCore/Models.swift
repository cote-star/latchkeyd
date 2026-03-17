import Foundation

public let latchkeydVersion = "0.1.0-alpha.3"

public struct CommandOutput: Codable {
    public let ok: Bool
    public let command: String
    public let message: String?
    public let data: [String: JSONValue]?

    public init(ok: Bool, command: String, message: String? = nil, data: [String: JSONValue]? = nil) {
        self.ok = ok
        self.command = command
        self.message = message
        self.data = data
    }
}

public struct ErrorOutput: Codable {
    public let ok: Bool
    public let error: ErrorBody

    public init(code: String, message: String, details: [String: JSONValue]? = nil) {
        self.ok = false
        self.error = ErrorBody(code: code, message: message, details: details)
    }
}

public struct ErrorBody: Codable {
    public let code: String
    public let message: String
    public let details: [String: JSONValue]?
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct Manifest: Codable {
    public let version: Int
    public let notes: [String]?
    public var backend: SecretBackendConfig
    public var wrappers: [String: TrustedPath]
    public var binaries: [String: TrustedBinary]
    public let secrets: [String: SecretSpec]
    public let operationSets: [String: OperationSet]?
    public let execPolicies: [String: ExecPolicy]

    public init(
        version: Int,
        notes: [String]? = nil,
        backend: SecretBackendConfig,
        wrappers: [String: TrustedPath],
        binaries: [String: TrustedBinary],
        secrets: [String: SecretSpec],
        operationSets: [String: OperationSet]? = nil,
        execPolicies: [String: ExecPolicy]
    ) {
        self.version = version
        self.notes = notes
        self.backend = backend
        self.wrappers = wrappers
        self.binaries = binaries
        self.secrets = secrets
        self.operationSets = operationSets
        self.execPolicies = execPolicies
    }
}

public struct SecretBackendConfig: Codable, Equatable {
    public let type: BackendType
    public let servicePrefix: String?
    public let account: String?
    public let filePath: String?

    public init(type: BackendType, servicePrefix: String? = nil, account: String? = nil, filePath: String? = nil) {
        self.type = type
        self.servicePrefix = servicePrefix
        self.account = account
        self.filePath = filePath
    }
}

public enum BackendType: String, Codable {
    case keychain
    case file
}

public enum ExecMode: String, Codable, CaseIterable {
    case handoff
    case oneshot
    case brokered
    case ephemeral
    case proxy
}

public struct TrustedPath: Codable, Equatable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) {
        self.path = path
        self.sha256 = sha256
    }
}

public struct TrustedBinary: Codable, Equatable {
    public let path: String
    public let sha256: String
    public let lookupName: String?

    public init(path: String, sha256: String, lookupName: String? = nil) {
        self.path = path
        self.sha256 = sha256
        self.lookupName = lookupName
    }
}

public struct SecretSpec: Codable, Equatable {
    public let envVar: String
    public let backendKey: String
    public let description: String?

    public init(envVar: String, backendKey: String, description: String? = nil) {
        self.envVar = envVar
        self.backendKey = backendKey
        self.description = description
    }
}

public struct ExecPolicy: Codable, Equatable {
    public let mode: ExecMode
    public let wrapper: String
    public let binary: String
    public let secrets: [String]
    public let operationSet: String?
    public let description: String?

    public init(
        mode: ExecMode = .handoff,
        wrapper: String,
        binary: String,
        secrets: [String],
        operationSet: String? = nil,
        description: String? = nil
    ) {
        self.mode = mode
        self.wrapper = wrapper
        self.binary = binary
        self.secrets = secrets
        self.operationSet = operationSet
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case wrapper
        case binary
        case secrets
        case operationSet
        case description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ExecMode.self, forKey: .mode) ?? .handoff
        wrapper = try container.decode(String.self, forKey: .wrapper)
        binary = try container.decode(String.self, forKey: .binary)
        secrets = try container.decode([String].self, forKey: .secrets)
        operationSet = try container.decodeIfPresent(String.self, forKey: .operationSet)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(wrapper, forKey: .wrapper)
        try container.encode(binary, forKey: .binary)
        try container.encode(secrets, forKey: .secrets)
        try container.encodeIfPresent(operationSet, forKey: .operationSet)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

public struct OperationSet: Codable, Equatable {
    public let operations: [OperationDefinition]

    public init(operations: [OperationDefinition]) {
        self.operations = operations
    }
}

public struct OperationDefinition: Codable, Equatable {
    public let name: OperationName
    public let allowedSecrets: [String]
    public let allowedResponseFields: [String]?

    public init(name: OperationName, allowedSecrets: [String], allowedResponseFields: [String]? = nil) {
        self.name = name
        self.allowedSecrets = allowedSecrets
        self.allowedResponseFields = allowedResponseFields
    }
}

public enum OperationName: String, Codable {
    case secretResolve = "secret.resolve"
}

public struct EventRecord: Codable {
    public let timestamp: String
    public let command: String
    public let result: String
    public let reason: String?
    public let backendType: String?
    public let wrapperName: String?
    public let wrapperPath: String?
    public let binaryName: String?
    public let binaryPath: String?
    public let policyMode: String?
    public let sessionId: String?
    public let operationName: String?
}

public struct ValidationItem: Codable {
    public let name: String
    public let ok: Bool
    public let message: String
}

public struct CLIContext {
    public let fileManager: FileManager
    public let environment: [String: String]
    public let currentDirectory: URL
    public let standardOutput: FileHandle
    public let standardError: FileHandle

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL? = nil,
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.currentDirectory = currentDirectory ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
