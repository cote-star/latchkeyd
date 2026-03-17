import Foundation

public struct ExecRequest {
    public let policyName: String
    public let callerPath: String
    public let arguments: [String]

    public init(policyName: String, callerPath: String, arguments: [String]) {
        self.policyName = policyName
        self.callerPath = callerPath
        self.arguments = arguments
    }
}

public struct BrokerService {
    private let manifest: Manifest
    private let backend: SecretBackend
    private let logger: EventLogger
    private let environment: [String: String]

    public init(manifest: Manifest, backend: SecretBackend, logger: EventLogger, environment: [String: String]) {
        self.manifest = manifest
        self.backend = backend
        self.logger = logger
        self.environment = environment
    }

    public func execute(_ request: ExecRequest) throws -> Int32 {
        var wrapperName: String?
        var wrapperPath: String?
        var binaryName: String?
        var binaryPath: String?
        var policyMode: ExecMode?
        try logger.prepare()

        do {
            guard let policy = manifest.execPolicies[request.policyName] else {
                throw LatchkeydError.usage("Unknown exec policy `\(request.policyName)`.")
            }
            guard let trustedWrapper = manifest.wrappers[policy.wrapper] else {
                throw LatchkeydError.manifest("Exec policy `\(request.policyName)` references unknown wrapper `\(policy.wrapper)`.")
            }
            guard let trustedBinary = manifest.binaries[policy.binary] else {
                throw LatchkeydError.manifest("Exec policy `\(request.policyName)` references unknown binary `\(policy.binary)`.")
            }

            let effectiveMode = effectiveMode(for: policy, policyName: request.policyName)
            policyMode = effectiveMode

            if effectiveMode == .oneshot, let rejectedArgument = rejectedOneshotArgument(in: request.arguments) {
                throw LatchkeydError.usage(
                    "Exec policy `\(request.policyName)` uses oneshot mode and rejects long-lived argument `\(rejectedArgument)`."
                )
            }

            wrapperName = policy.wrapper
            binaryName = policy.binary

            try ensureOneshotCompliance(mode: effectiveMode, request: request)

            let callerPath = canonicalPath(request.callerPath)
            let trustedWrapperPath = canonicalPath(trustedWrapper.path)
            wrapperPath = trustedWrapperPath
            try verifyTrustedPath(
                actualPath: callerPath,
                trustedPath: trustedWrapperPath,
                expectedSHA256: trustedWrapper.sha256,
                entryName: policy.wrapper,
                kind: .wrapper
            )

            let trustedBinaryPath = canonicalPath(trustedBinary.path)
            binaryPath = trustedBinaryPath
            try verifyTrustedPath(
                actualPath: trustedBinaryPath,
                trustedPath: trustedBinaryPath,
                expectedSHA256: trustedBinary.sha256,
                entryName: policy.binary,
                kind: .binary
            )

            if let lookupName = trustedBinary.lookupName {
                guard let resolved = resolveExecutable(named: lookupName, environment: environment) else {
                    throw LatchkeydError.trust(
                        "Expected executable `\(lookupName)` was not found in PATH.",
                        ["binary": .string(policy.binary), "lookupName": .string(lookupName)]
                    )
                }
                guard resolved == trustedBinaryPath else {
                    throw LatchkeydError.trust(
                        "PATH hijack detected for trusted binary `\(policy.binary)`.",
                        [
                            "binary": .string(policy.binary),
                            "lookupName": .string(lookupName),
                            "resolvedPath": .string(resolved),
                            "trustedPath": .string(trustedBinaryPath)
                        ]
                    )
                }
            }

            if effectiveMode == .brokered {
                let status = try executeBrokered(
                    request: request,
                    policy: policy,
                    mode: effectiveMode,
                    trustedWrapperPath: trustedWrapperPath,
                    trustedBinaryPath: trustedBinaryPath
                )
                return status
            }

            if effectiveMode == .ephemeral || effectiveMode == .proxy {
                throw LatchkeydError.usage("Exec policy `\(request.policyName)` uses mode `\(effectiveMode.rawValue)`, which is not implemented yet.")
            }

            var childEnvironment = environment
            for secretName in policy.secrets {
                guard let secret = manifest.secrets[secretName] else {
                    throw LatchkeydError.manifest("Exec policy `\(request.policyName)` references unknown secret `\(secretName)`.")
                }
                let value = try backend.resolveSecret(spec: secret)
                childEnvironment[secret.envVar] = value
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: trustedBinaryPath)
            process.arguments = request.arguments
            process.environment = childEnvironment
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            process.standardInput = FileHandle.standardInput

            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                try logger.log(
                    command: "exec",
                    result: "ok",
                    backendType: backend.type,
                    policyMode: effectiveMode,
                    wrapperName: policy.wrapper,
                    wrapperPath: trustedWrapperPath,
                    binaryName: policy.binary,
                    binaryPath: trustedBinaryPath
                )
            } else {
                try logger.log(
                    command: "exec",
                    result: "failed",
                    reason: "child_exit_\(process.terminationStatus)",
                    backendType: backend.type,
                    policyMode: effectiveMode,
                    wrapperName: wrapperName,
                    wrapperPath: trustedWrapperPath,
                    binaryName: binaryName,
                    binaryPath: trustedBinaryPath
                )
            }
            return process.terminationStatus
        } catch let error as LatchkeydError {
            let logShape = error.logShape
            do {
                try logger.log(
                    command: "exec",
                    result: logShape.result,
                    reason: logShape.reason,
                    backendType: backend.type,
                    policyMode: policyMode ?? manifest.execPolicies[request.policyName]?.mode,
                    wrapperName: wrapperName,
                    wrapperPath: wrapperPath,
                    binaryName: binaryName,
                    binaryPath: binaryPath
                )
            } catch let loggingError as LatchkeydError {
                throw enrichLoggingError(loggingError, command: "exec", originalError: error)
            }
            throw error
        } catch {
            let executionError = LatchkeydError.execution(
                "Failed to launch trusted binary `\(binaryPath ?? "<unknown>")`: \(error.localizedDescription)",
                nil
            )
            do {
                try logger.log(
                    command: "exec",
                    result: "failed",
                    reason: "unexpected_error",
                    backendType: backend.type,
                    policyMode: policyMode ?? manifest.execPolicies[request.policyName]?.mode,
                    wrapperName: wrapperName,
                    wrapperPath: wrapperPath,
                    binaryName: binaryName,
                    binaryPath: binaryPath
                )
            } catch let loggingError as LatchkeydError {
                throw enrichLoggingError(loggingError, command: "exec", originalError: executionError)
            }
            throw executionError
        }
    }

    private func executeBrokered(
        request: ExecRequest,
        policy: ExecPolicy,
        mode: ExecMode,
        trustedWrapperPath: String,
        trustedBinaryPath: String
    ) throws -> Int32 {
        let session = try BrokeredSessionServer(
            manifest: manifest,
            policyName: request.policyName,
            policy: policy,
            backend: backend,
            logger: logger,
            wrapperName: policy.wrapper,
            wrapperPath: trustedWrapperPath,
            binaryName: policy.binary,
            binaryPath: trustedBinaryPath
        )
        try session.start()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: trustedBinaryPath)
        process.arguments = request.arguments
        process.environment = environment.merging(session.environment) { _, new in new }
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.standardInput = FileHandle.standardInput

        do {
            try process.run()
        } catch {
            try? session.stop(reason: "launch_failed")
            throw LatchkeydError.execution(
                "Failed to launch trusted binary `\(trustedBinaryPath)`: \(error.localizedDescription)",
                nil
            )
        }

        try session.attachChild(pid: process.processIdentifier)
        process.waitUntilExit()

        do {
            try session.stop(reason: "terminated")
        } catch let loggingError as LatchkeydError {
            throw enrichLoggingError(loggingError, command: "exec", originalError: .execution("Brokered session teardown failed.", process.terminationStatus))
        }

        try session.rethrowFatalErrorIfNeeded()

        if process.terminationStatus == 0 {
            try logger.log(
                command: "exec",
                result: "ok",
                backendType: backend.type,
                policyMode: mode,
                wrapperName: policy.wrapper,
                wrapperPath: trustedWrapperPath,
                binaryName: policy.binary,
                binaryPath: trustedBinaryPath,
                sessionId: session.sessionId
            )
        } else {
            try logger.log(
                command: "exec",
                result: "failed",
                reason: "child_exit_\(process.terminationStatus)",
                backendType: backend.type,
                policyMode: mode,
                wrapperName: policy.wrapper,
                wrapperPath: trustedWrapperPath,
                binaryName: policy.binary,
                binaryPath: trustedBinaryPath,
                sessionId: session.sessionId
            )
        }

        return process.terminationStatus
    }

    private func verifyTrustedPath(
        actualPath: String,
        trustedPath: String,
        expectedSHA256: String,
        entryName: String,
        kind: PathKind
    ) throws {
        guard actualPath == trustedPath else {
            throw LatchkeydError.trust(
                "Trusted \(kind == .wrapper ? "wrapper" : "binary") path mismatch for `\(entryName)`.",
                [
                    "entry": .string(entryName),
                    "actualPath": .string(actualPath),
                    "trustedPath": .string(trustedPath)
                ]
            )
        }

        guard fileExists(trustedPath) else {
            throw LatchkeydError.trust(
                "Trusted \(kind == .wrapper ? "wrapper" : "binary") path is missing.",
                ["entry": .string(entryName), "path": .string(trustedPath)]
            )
        }

        let digest = try sha256(forFileAtPath: trustedPath)
        guard digest == expectedSHA256 else {
            throw LatchkeydError.trust(
                "Trusted \(kind == .wrapper ? "wrapper" : "binary") hash mismatch for `\(entryName)`.",
                ["entry": .string(entryName), "path": .string(trustedPath)]
            )
        }
    }

    private func enrichLoggingError(
        _ loggingError: LatchkeydError,
        command: String,
        originalError: LatchkeydError
    ) -> LatchkeydError {
        guard case .logging(let message, let details) = loggingError else {
            return loggingError
        }

        var mergedDetails = details ?? [:]
        mergedDetails["command"] = .string(command)
        mergedDetails["originalErrorCode"] = .string(originalError.errorOutput.error.code)
        return .logging(message, mergedDetails)
    }

    private func ensureOneshotCompliance(mode: ExecMode, request: ExecRequest) throws {
        guard mode == .oneshot else {
            return
        }
        let forbidden = ["--watch", "--daemon", "--serve", "--background"]
        let offending = request.arguments.first { arg in
            let lower = arg.lowercased()
            return forbidden.contains(where: { lower.contains($0) })
        }
        if let offender = offending {
            throw LatchkeydError.usage("Oneshot mode rejects the argument `\(offender)` because it indicates a long-lived run.")
        }
    }

    private func effectiveMode(for policy: ExecPolicy, policyName: String) -> ExecMode {
        if policy.mode != .handoff {
            return policy.mode
        }
        return manifest.executionMode(forPolicy: policyName) == .oneshot ? .oneshot : .handoff
    }
}
