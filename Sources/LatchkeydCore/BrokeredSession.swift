import Darwin
import Foundation

struct BrokeredRequest: Codable {
    let version: Int
    let sessionId: String
    let sessionToken: String
    let operation: String
    let arguments: [String: String]
}

struct BrokeredResponse: Codable {
    let ok: Bool
    let operation: String
    let data: [String: JSONValue]?
    let error: ErrorBody?

    static func success(operation: String, data: [String: JSONValue]) -> BrokeredResponse {
        BrokeredResponse(ok: true, operation: operation, data: data, error: nil)
    }

    static func failure(operation: String, code: String, message: String, details: [String: JSONValue]? = nil) -> BrokeredResponse {
        BrokeredResponse(ok: false, operation: operation, data: nil, error: ErrorBody(code: code, message: message, details: details))
    }
}

final class BrokeredSessionServer: @unchecked Sendable {
    private let manifest: Manifest
    private let policyName: String
    private let policy: ExecPolicy
    private let backend: SecretBackend
    private let logger: EventLogger
    private let wrapperName: String
    private let wrapperPath: String
    private let binaryName: String
    private let binaryPath: String
    private let fileManager: FileManager
    private let lock = NSLock()
    private let acceptQueue = DispatchQueue(label: "LatchkeydCore.BrokeredSessionServer")
    private let sessionDirectory: URL

    let sessionId: String
    let sessionToken: String
    let socketPath: String

    private let listeningFD: Int32
    private let createdAt: Date
    private let expiresAt: Date
    private var lastActivityAt: Date
    private var launchedPID: Int32?
    private var shouldStop = false
    private var fatalError: LatchkeydError?

    init(
        manifest: Manifest,
        policyName: String,
        policy: ExecPolicy,
        backend: SecretBackend,
        logger: EventLogger,
        wrapperName: String,
        wrapperPath: String,
        binaryName: String,
        binaryPath: String,
        fileManager: FileManager = .default
    ) throws {
        self.manifest = manifest
        self.policyName = policyName
        self.policy = policy
        self.backend = backend
        self.logger = logger
        self.wrapperName = wrapperName
        self.wrapperPath = wrapperPath
        self.binaryName = binaryName
        self.binaryPath = binaryPath
        self.fileManager = fileManager

        createdAt = Date()
        lastActivityAt = createdAt
        expiresAt = createdAt.addingTimeInterval(300)
        sessionId = UUID().uuidString.lowercased()
        sessionToken = UUID().uuidString.lowercased()
        sessionDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("lkd-\(String(sessionId.prefix(12)))", isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        socketPath = sessionDirectory.appendingPathComponent("session.sock").path

        listeningFD = Darwin.socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard listeningFD >= 0 else {
            try? fileManager.removeItem(at: sessionDirectory)
            throw posixBrokeredError("SESSION_CREATION_ERROR", message: "Failed to create brokered session socket.", code: errno)
        }

        do {
            try bindAndListen()
        } catch {
            Darwin.close(listeningFD)
            try? fileManager.removeItem(at: sessionDirectory)
            throw error
        }
    }

    deinit {
        Darwin.close(listeningFD)
        _ = Darwin.unlink(socketPath)
        try? fileManager.removeItem(at: sessionDirectory)
    }

    var environment: [String: String] {
        [
            "LATCHKEYD_SESSION_SOCKET": socketPath,
            "LATCHKEYD_SESSION_ID": sessionId,
            "LATCHKEYD_SESSION_TOKEN": sessionToken,
            "LATCHKEYD_POLICY_NAME": policyName,
            "LATCHKEYD_POLICY_MODE": policy.mode.rawValue,
        ]
    }

    func start() throws {
        try logger.log(
            command: "brokered.session",
            result: "ok",
            reason: "created",
            backendType: backend.type,
            policyMode: policy.mode,
            wrapperName: wrapperName,
            wrapperPath: wrapperPath,
            binaryName: binaryName,
            binaryPath: binaryPath,
            sessionId: sessionId
        )

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func attachChild(pid: Int32) throws {
        lock.lock()
        launchedPID = pid
        lock.unlock()

        try logger.log(
            command: "brokered.session",
            result: "ok",
            reason: "active",
            backendType: backend.type,
            policyMode: policy.mode,
            wrapperName: wrapperName,
            wrapperPath: wrapperPath,
            binaryName: binaryName,
            binaryPath: binaryPath,
            sessionId: sessionId
        )
    }

    func stop(reason: String) throws {
        lock.lock()
        shouldStop = true
        lock.unlock()

        Darwin.shutdown(listeningFD, SHUT_RDWR)
        _ = Darwin.unlink(socketPath)

        try logger.log(
            command: "brokered.session",
            result: "ok",
            reason: reason,
            backendType: backend.type,
            policyMode: policy.mode,
            wrapperName: wrapperName,
            wrapperPath: wrapperPath,
            binaryName: binaryName,
            binaryPath: binaryPath,
            sessionId: sessionId
        )
    }

    func rethrowFatalErrorIfNeeded() throws {
        lock.lock()
        let error = fatalError
        lock.unlock()
        if let error {
            throw error
        }
    }

    private func bindAndListen() throws {
        _ = Darwin.unlink(socketPath)

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let maxBytes = MemoryLayout.size(ofValue: address.sun_path) - 1
        socketPath.utf8CString.withUnsafeBufferPointer { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: Int8.self, capacity: source.count) { destinationBuffer in
                    let stringBytes = max(0, source.count - 1)
                    let copyCount = min(maxBytes, stringBytes)
                    memcpy(destinationBuffer, source.baseAddress, copyCount)
                    destinationBuffer[copyCount] = 0
                }
            }
        }

        let addressLength = socklen_t(address.sun_len)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(listeningFD, pointer, addressLength)
            }
        }
        guard bindResult == 0 else {
            throw posixBrokeredError("SESSION_CREATION_ERROR", message: "Failed to bind brokered session socket.", code: errno)
        }

        guard Darwin.listen(listeningFD, 8) == 0 else {
            throw posixBrokeredError("SESSION_CREATION_ERROR", message: "Failed to listen on brokered session socket.", code: errno)
        }
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let stopping = shouldStop
            lock.unlock()
            if stopping {
                return
            }

            let clientFD = Darwin.accept(listeningFD, nil, nil)
            if clientFD < 0 {
                lock.lock()
                let stoppingNow = shouldStop
                lock.unlock()
                if stoppingNow {
                    return
                }
                recordFatalError(posixBrokeredError("SESSION_PROTOCOL_ERROR", message: "Failed to accept brokered session connection.", code: errno))
                return
            }

            do {
                try handleClient(clientFD)
            } catch let error as LatchkeydError {
                let response = brokeredFailureResponse(for: error)
                try? writeResponse(response, to: clientFD)

                switch error {
                case .logging, .io, .execution:
                    recordFatalError(error)
                case .brokered(let code, _, _):
                    if code == "LOGGING_ERROR" || code == "SESSION_PROTOCOL_ERROR" || code == "SESSION_CREATION_ERROR" {
                        recordFatalError(error)
                    }
                default:
                    break
                }
            } catch {
                recordFatalError(.brokered("SESSION_PROTOCOL_ERROR", "Unexpected brokered session error: \(error.localizedDescription)", nil))
            }

            Darwin.close(clientFD)
        }
    }

    private func handleClient(_ clientFD: Int32) throws {
        let line = try readLine(from: clientFD)
        guard let requestData = line.data(using: .utf8) else {
            throw LatchkeydError.brokered("SESSION_PROTOCOL_ERROR", "Brokered request was not valid UTF-8.", nil)
        }

        let request: BrokeredRequest
        do {
            request = try JSONDecoder().decode(BrokeredRequest.self, from: requestData)
        } catch {
            throw LatchkeydError.brokered("SESSION_PROTOCOL_ERROR", "Brokered request could not be decoded.", nil)
        }

        try validate(request: request)
        let operation = try operationDefinition(for: request.operation)
        let response = try perform(request: request, operation: operation)
        try writeResponse(response, to: clientFD)
    }

    private func validate(request: BrokeredRequest) throws {
        guard request.version == 1 else {
            throw LatchkeydError.brokered("SESSION_PROTOCOL_ERROR", "Unsupported brokered request version `\(request.version)`.", nil)
        }
        guard request.sessionId == sessionId, request.sessionToken == sessionToken else {
            let error = LatchkeydError.brokered("SESSION_AUTH_ERROR", "Brokered request authentication failed.", ["sessionId": .string(request.sessionId)])
            try logBrokeredRequest(result: "denied", reason: "session_auth_error", operationName: request.operation)
            throw error
        }

        let now = Date()
        if now > expiresAt {
            let error = LatchkeydError.brokered("SESSION_EXPIRED", "Brokered session expired before the request was handled.", ["sessionId": .string(sessionId)])
            try logBrokeredRequest(result: "failed", reason: "session_expired", operationName: request.operation)
            throw error
        }

        if now.timeIntervalSince(lastActivityAt) > 60 {
            let error = LatchkeydError.brokered("SESSION_EXPIRED", "Brokered session idle timeout elapsed before the request was handled.", ["sessionId": .string(sessionId)])
            try logBrokeredRequest(result: "failed", reason: "session_idle_timeout", operationName: request.operation)
            throw error
        }
    }

    private func operationDefinition(for operationName: String) throws -> OperationDefinition {
        guard let operationSetName = policy.operationSet,
              let operationSet = manifest.operationSets?[operationSetName] else {
            throw LatchkeydError.manifest("Brokered policy `\(policyName)` requires a valid operationSet before execution.")
        }

        guard let operation = operationSet.operations.first(where: { $0.name.rawValue == operationName }) else {
            try logBrokeredRequest(result: "denied", reason: "operation_not_allowed", operationName: operationName)
            throw LatchkeydError.brokered(
                "OPERATION_NOT_ALLOWED",
                "Brokered operation `\(operationName)` is not allowed for policy `\(policyName)`.",
                ["policy": .string(policyName), "operation": .string(operationName)]
            )
        }
        return operation
    }

    private func perform(request: BrokeredRequest, operation: OperationDefinition) throws -> BrokeredResponse {
        switch operation.name {
        case .secretResolve:
            guard let secretName = request.arguments["secretName"], !secretName.isEmpty else {
                throw LatchkeydError.brokered("SESSION_PROTOCOL_ERROR", "Brokered request `secret.resolve` requires `arguments.secretName`.", nil)
            }
            guard operation.allowedSecrets.contains(secretName), policy.secrets.contains(secretName) else {
                try logBrokeredRequest(result: "denied", reason: "operation_not_allowed", operationName: operation.name.rawValue)
                throw LatchkeydError.brokered(
                    "OPERATION_NOT_ALLOWED",
                    "Secret `\(secretName)` is not allowed for brokered operation `\(operation.name.rawValue)`.",
                    ["secretName": .string(secretName), "operation": .string(operation.name.rawValue)]
                )
            }
            guard let secretSpec = manifest.secrets[secretName] else {
                throw LatchkeydError.manifest("Brokered policy `\(policyName)` references unknown secret `\(secretName)`.")
            }
            let secretValue = try backend.resolveSecret(spec: secretSpec)
            lastActivityAt = Date()
            try logBrokeredRequest(result: "ok", reason: operation.name.rawValue, operationName: operation.name.rawValue)

            var data: [String: JSONValue] = [
                "secretName": .string(secretName),
                "value": .string(secretValue),
            ]
            if operation.allowedResponseFields?.contains("lifetimeSeconds") ?? false {
                data["lifetimeSeconds"] = .int(60)
            }
            return .success(operation: operation.name.rawValue, data: data)
        }
    }

    private func logBrokeredRequest(result: String, reason: String, operationName: String) throws {
        try logger.log(
            command: "brokered.request",
            result: result,
            reason: reason,
            backendType: backend.type,
            policyMode: policy.mode,
            wrapperName: wrapperName,
            wrapperPath: wrapperPath,
            binaryName: binaryName,
            binaryPath: binaryPath,
            sessionId: sessionId,
            operationName: operationName
        )
    }

    private func readLine(from fd: Int32) throws -> String {
        var buffer = Data()
        var byte: UInt8 = 0

        while true {
            let bytesRead = Darwin.read(fd, &byte, 1)
            if bytesRead < 0 {
                throw posixBrokeredError("SESSION_PROTOCOL_ERROR", message: "Failed to read brokered session request.", code: errno)
            }
            if bytesRead == 0 || byte == 0x0A {
                break
            }
            buffer.append(byte)
            if buffer.count > 65_536 {
                throw LatchkeydError.brokered("SESSION_PROTOCOL_ERROR", "Brokered request exceeded the maximum supported size.", nil)
            }
        }

        guard let line = String(data: buffer, encoding: .utf8) else {
            throw LatchkeydError.brokered("SESSION_PROTOCOL_ERROR", "Brokered request was not valid UTF-8.", nil)
        }
        return line
    }

    private func writeResponse(_ response: BrokeredResponse, to fd: Int32) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(response) + Data("\n".utf8)
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let chunk = Darwin.write(fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if chunk < 0 {
                    throw posixBrokeredError("SESSION_PROTOCOL_ERROR", message: "Failed to write brokered session response.", code: errno)
                }
                written += chunk
            }
        }
    }

    private func brokeredFailureResponse(for error: LatchkeydError) -> BrokeredResponse {
        let errorOutput = error.errorOutput
        return .failure(
            operation: "unknown",
            code: errorOutput.error.code,
            message: errorOutput.error.message,
            details: errorOutput.error.details
        )
    }

    private func recordFatalError(_ error: LatchkeydError) {
        lock.lock()
        if fatalError == nil {
            fatalError = error
        }
        lock.unlock()
    }
}

private func posixBrokeredError(_ code: String, message: String, code errorCode: Int32) -> LatchkeydError {
    .brokered(code, message, ["errno": .int(Int(errorCode))])
}
