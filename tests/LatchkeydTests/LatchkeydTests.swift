import Foundation
import Testing
@testable import LatchkeydCore

struct LatchkeydTests {
    @Test
    func manifestLoadRejectsMalformedJSON() throws {
        let temp = try temporaryDirectory()
        let manifestURL = temp.appendingPathComponent("manifest.json")
        try Data("{ not valid json".utf8).write(to: manifestURL)
        let store = ManifestStore(manifestURL: manifestURL, currentDirectory: temp)

        #expect(throws: LatchkeydError.self) {
            _ = try store.load()
        }
    }

    @Test
    func manifestInitCreatesExpectedEntries() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let store = ManifestStore(manifestURL: manifestURL, currentDirectory: repo)

        let manifest = try store.initialize(force: true)

        #expect(manifest.backend.type == .file)
        #expect(manifest.wrappers["example-wrapper"] != nil)
        #expect(manifest.binaries["example-cli"]?.lookupName == "example-demo-cli")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    @Test
    func manifestVerifyRejectsWrapperHashDrift() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let store = ManifestStore(manifestURL: manifestURL, currentDirectory: repo)
        _ = try store.initialize(force: true)

        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper")
        try Data("#!/usr/bin/env bash\necho drifted\n".utf8).write(to: wrapperPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath.path)

        #expect(throws: LatchkeydError.self) {
            _ = try store.verify()
        }
    }

    @Test
    func fileBackendResolvesFixtureSecret() throws {
        let temp = try temporaryDirectory()
        let secretsURL = temp.appendingPathComponent("secrets.json")
        try Data(#"{"example-token":"fixture-token"}"#.utf8).write(to: secretsURL)

        let backend = FileSecretBackend(filePath: secretsURL.path)
        let value = try backend.resolveSecret(spec: SecretSpec(envVar: "EXAMPLE_TOKEN", backendKey: "example-token"))

        #expect(value == "fixture-token")
    }

    @Test
    func brokerDeniesWhenCallerPathDoesNotMatchTrustedWrapper() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path

        let manifest = Manifest(
            version: 1,
            backend: SecretBackendConfig(type: .file, filePath: secretsURL),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(path: binaryPath, sha256: try sha256(forFileAtPath: binaryPath), lookupName: "example-demo-cli")
            ],
            secrets: [
                "example-token": SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            ],
            execPolicies: [
                "example-demo": ExecPolicy(wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
            ]
        )

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: temp.appendingPathComponent("events.jsonl"))
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        )

        #expect(throws: LatchkeydError.self) {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: "/tmp/not-the-wrapper.sh", arguments: ["smoke"])
            )
        }
    }

    @Test
    func brokerSuccessLogsEventWithoutSecretLeakage() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path
        let secretValue = "fixture-token"
        let eventsURL = temp.appendingPathComponent("events.jsonl")

        let manifest = Manifest(
            version: 1,
            backend: SecretBackendConfig(type: .file, filePath: secretsURL),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(path: binaryPath, sha256: try sha256(forFileAtPath: binaryPath), lookupName: "example-demo-cli")
            ],
            secrets: [
                "example-token": SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            ],
            execPolicies: [
                "example-demo": ExecPolicy(wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
            ]
        )

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: eventsURL)
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        )

        let status = try service.execute(
            ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: [])
        )

        #expect(status == 0)
        let events = try decodeEventRecords(at: eventsURL)
        #expect(events.count == 1)
        #expect(events.first?.command == "exec")
        #expect(events.first?.result == "ok")
        #expect(events.first?.reason == nil)
        #expect(events.first?.wrapperName == "example-wrapper")
        #expect(events.first?.binaryName == "example-cli")
        let contents = try String(contentsOf: eventsURL, encoding: .utf8)
        #expect(!contents.contains(secretValue))
    }

    @Test
    func trustedBinaryLookupDetectsHijackedPath() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path
        let hijackDirectory = temp.appendingPathComponent("hijack")
        try FileManager.default.createDirectory(at: hijackDirectory, withIntermediateDirectories: true)
        let hijackBinary = hijackDirectory.appendingPathComponent("example-demo-cli")
        try Data("#!/usr/bin/env bash\necho hijacked\n".utf8).write(to: hijackBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hijackBinary.path)

        let manifest = Manifest(
            version: 1,
            backend: SecretBackendConfig(type: .file, filePath: secretsURL),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(path: binaryPath, sha256: try sha256(forFileAtPath: binaryPath), lookupName: "example-demo-cli")
            ],
            secrets: [
                "example-token": SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            ],
            execPolicies: [
                "example-demo": ExecPolicy(wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
            ]
        )

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: temp.appendingPathComponent("events.jsonl"))
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(hijackDirectory.path):\(repo.appendingPathComponent("examples/bin").path)"]
        )

        #expect(throws: LatchkeydError.self) {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: [])
            )
        }

        let events = try decodeEventRecords(at: temp.appendingPathComponent("events.jsonl"))
        #expect(events.count == 1)
        #expect(events.first?.result == "denied")
        #expect(events.first?.reason == "trust_denied")
    }

    @Test
    func brokerDeniesWhenFileBackendIsMisconfigured() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let missingSecretsPath = repo.appendingPathComponent("examples/file-backend/missing.json").path
        let eventsURL = temp.appendingPathComponent("events.jsonl")

        let manifest = Manifest(
            version: 1,
            backend: SecretBackendConfig(type: .file, filePath: missingSecretsPath),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(path: binaryPath, sha256: try sha256(forFileAtPath: binaryPath), lookupName: "example-demo-cli")
            ],
            secrets: [
                "example-token": SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            ],
            execPolicies: [
                "example-demo": ExecPolicy(wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
            ]
        )

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: eventsURL)
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        )

        #expect(throws: LatchkeydError.self) {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: [])
            )
        }

        let events = try decodeEventRecords(at: eventsURL)
        #expect(events.count == 1)
        #expect(events.first?.result == "denied")
        #expect(events.first?.reason == "backend_error")
    }

    @Test
    func keychainBackendAvailabilityCheckIsMacOSGated() throws {
        let backend = KeychainSecretBackend(servicePrefix: "latchkeyd", account: NSUserName())
        try backend.availabilityCheck()
    }

    @Test
    func brokerExecutionFailsWhenEventLogPreflightFails() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path
        let brokenEventsURL = temp.appendingPathComponent("events-as-directory")
        try FileManager.default.createDirectory(at: brokenEventsURL, withIntermediateDirectories: true)

        let manifest = Manifest(
            version: 1,
            backend: SecretBackendConfig(type: .file, filePath: secretsURL),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(path: binaryPath, sha256: try sha256(forFileAtPath: binaryPath), lookupName: "example-demo-cli")
            ],
            secrets: [
                "example-token": SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            ],
            execPolicies: [
                "example-demo": ExecPolicy(wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
            ]
        )

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: brokenEventsURL)
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        )

        do {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: [])
            )
            Issue.record("Expected logging preflight failure when events path is unavailable.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "LOGGING_ERROR")
            #expect(error.errorOutput.error.details?["auditStatus"] == .string("unavailable"))
        }
    }

    @Test
    func brokerExecutionFailsWhenLogAppendFailsAfterChildExit() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path
        let eventsURL = temp.appendingPathComponent("events.jsonl")

        let manifest = Manifest(
            version: 1,
            backend: SecretBackendConfig(type: .file, filePath: secretsURL),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(path: binaryPath, sha256: try sha256(forFileAtPath: binaryPath), lookupName: "example-demo-cli")
            ],
            secrets: [
                "example-token": SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            ],
            execPolicies: [
                "example-demo": ExecPolicy(wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
            ]
        )

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: eventsURL) { _, _ in
            throw NSError(domain: "LatchkeydTests", code: 77, userInfo: [NSLocalizedDescriptionKey: "append blocked"])
        }
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        )

        do {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: [])
            )
            Issue.record("Expected append failure to override child success with LOGGING_ERROR.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "LOGGING_ERROR")
            #expect(error.errorOutput.error.details?["auditStatus"] == .string("incomplete"))
        }
    }

    @Test
    func brokerExecFailsWhenEventLogIsUnavailable() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let eventsDir = temp.appendingPathComponent("events-unavailable")
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        let manifestStore = ManifestStore(manifestURL: manifestURL, currentDirectory: repo)
        _ = try manifestStore.initialize(force: true)
        let manifest = try manifestStore.load()

        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
        let logger = EventLogger(eventsURL: eventsDir)
        let service = BrokerService(
            manifest: manifest,
            backend: backend,
            logger: logger,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        )

        do {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: [])
            )
            Issue.record("Expected logging preflight to reject exec when events path is unavailable.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "LOGGING_ERROR")
            #expect(error.errorOutput.error.details?["auditStatus"] == .string("unavailable"))
        }
    }

    @Test
    func validatorFailsWhenEventLogIsUnavailable() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let eventsDir = temp.appendingPathComponent("events-unavailable")
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        let manifestStore = ManifestStore(manifestURL: manifestURL, currentDirectory: repo)
        _ = try manifestStore.initialize(force: true)

        _ = try manifestStore.load()
        let logger = EventLogger(eventsURL: eventsDir)
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let latchkeydBin = repoRoot.appendingPathComponent(".build/debug/latchkeyd")
        let validator = Validator(
            manifestURL: manifestURL,
            manifestStore: manifestStore,
            environment: ["PATH": "\(repo.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"],
            logger: logger
        )

        do {
            _ = try validator.run(selfExecutablePath: latchkeydBin.path)
            Issue.record("Expected validate to fail when event logging cannot warm up.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "LOGGING_ERROR")
            #expect(error.errorOutput.error.details?["auditStatus"] == .string("unavailable"))
        }
    }

    @Test
    func execCommandParsingSupportsZeroAndTrailingArguments() throws {
        let appPaths = try AppPaths.resolve(fileManager: .default)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let withoutTrailingArgs = try ParsedCommand(
            arguments: ["exec", "--policy", "example-demo", "--caller", "/tmp/example-wrapper"],
            appPaths: appPaths,
            currentDirectory: cwd
        )
        switch withoutTrailingArgs.command {
        case .exec(let request):
            #expect(request.policyName == "example-demo")
            #expect(request.callerPath == "/tmp/example-wrapper")
            #expect(request.arguments.isEmpty)
        default:
            Issue.record("Expected exec command shape for zero-arg parsing")
        }

        let withTrailingArgs = try ParsedCommand(
            arguments: ["exec", "--manifest", "/tmp/manifest.json", "--policy", "example-demo", "--caller", "/tmp/example-wrapper", "--", "raw", "beta"],
            appPaths: appPaths,
            currentDirectory: cwd
        )
        switch withTrailingArgs.command {
        case .exec(let request):
            #expect(request.policyName == "example-demo")
            #expect(request.callerPath == "/tmp/example-wrapper")
            #expect(request.arguments == ["raw", "beta"])
        default:
            Issue.record("Expected exec command shape for trailing args parsing")
        }
    }

    @Test
    func rawExecAndWrapperDemoForwardArgumentsToDemoCLI() throws {
        let temp = try temporaryDirectory()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let latchkeydBin = repoRoot.appendingPathComponent(".build/debug/latchkeyd")
        let wrapper = repoRoot.appendingPathComponent("examples/bin/example-wrapper")
        let manifestURL = temp.appendingPathComponent("manifest.json")

        #expect(FileManager.default.isExecutableFile(atPath: latchkeydBin.path))
        #expect(FileManager.default.isExecutableFile(atPath: wrapper.path))

        let baseEnvironment = [
            "LATCHKEYD_BIN": latchkeydBin.path,
            "PATH": "\(repoRoot.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]

        let initResult = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "init", "--manifest", manifestURL.path, "--force"],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )
        #expect(initResult.status == 0)

        let refreshResult = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "refresh", "--manifest", manifestURL.path],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )
        #expect(refreshResult.status == 0)

        let rawExecWithoutArgs = try runProcess(
            executable: latchkeydBin.path,
            arguments: [
                "exec",
                "--manifest", manifestURL.path,
                "--policy", "example-demo",
                "--caller", wrapper.path
            ],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )
        #expect(rawExecWithoutArgs.status == 0)
        let rawExecWithoutArgsOutput = try decodeDemoCLIOutput(rawExecWithoutArgs.stdout)
        #expect(rawExecWithoutArgsOutput.ok)
        #expect(rawExecWithoutArgsOutput.args.isEmpty)

        let rawExecWithArgs = try runProcess(
            executable: latchkeydBin.path,
            arguments: [
                "exec",
                "--manifest", manifestURL.path,
                "--policy", "example-demo",
                "--caller", wrapper.path,
                "--", "raw", "beta"
            ],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )
        #expect(rawExecWithArgs.status == 0)
        let rawExecWithArgsOutput = try decodeDemoCLIOutput(rawExecWithArgs.stdout)
        #expect(rawExecWithArgsOutput.ok)
        #expect(rawExecWithArgsOutput.args == ["raw", "beta"])

        let wrapperDemoWithoutArgs = try runProcess(
            executable: "/bin/bash",
            arguments: [wrapper.path, "demo", "--manifest", manifestURL.path],
            environment: ["LATCHKEYD_BIN": latchkeydBin.path],
            currentDirectory: repoRoot
        )
        #expect(wrapperDemoWithoutArgs.status == 0)
        let wrapperDemoWithoutArgsOutput = try decodeDemoCLIOutput(wrapperDemoWithoutArgs.stdout)
        #expect(wrapperDemoWithoutArgsOutput.ok)
        #expect(wrapperDemoWithoutArgsOutput.args.isEmpty)

        let wrapperDemoWithArgs = try runProcess(
            executable: "/bin/bash",
            arguments: [wrapper.path, "demo", "--manifest", manifestURL.path, "smoke", "alpha"],
            environment: ["LATCHKEYD_BIN": latchkeydBin.path],
            currentDirectory: repoRoot
        )
        #expect(wrapperDemoWithArgs.status == 0)
        let wrapperDemoWithArgsOutput = try decodeDemoCLIOutput(wrapperDemoWithArgs.stdout)
        #expect(wrapperDemoWithArgsOutput.ok)
        #expect(wrapperDemoWithArgsOutput.args == ["smoke", "alpha"])
    }

    @Test
    func cliStatusAndManifestVerifyEmitStructuredJSON() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let latchkeydBin = repoRoot.appendingPathComponent(".build/debug/latchkeyd")
        let manifestURL = try temporaryDirectory().appendingPathComponent("manifest.json")

        let initResult = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "init", "--manifest", manifestURL.path, "--force"],
            environment: [:],
            currentDirectory: repoRoot
        )
        #expect(initResult.status == 0)
        let initOutput = try decodeCommandOutput(initResult.stdout)
        #expect(initOutput.ok)
        #expect(initOutput.command == "manifest.init")

        let statusResult = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["status", "--manifest", manifestURL.path],
            environment: [:],
            currentDirectory: repoRoot
        )
        #expect(statusResult.status == 0)
        let statusOutput = try decodeCommandOutput(statusResult.stdout)
        #expect(statusOutput.ok)
        #expect(statusOutput.command == "status")
        #expect(statusOutput.data?["manifestPath"] == .string(manifestURL.path))

        let refreshResult = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "refresh", "--manifest", manifestURL.path],
            environment: [:],
            currentDirectory: repoRoot
        )
        #expect(refreshResult.status == 0)

        let verifyResult = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "verify", "--manifest", manifestURL.path],
            environment: [:],
            currentDirectory: repoRoot
        )
        #expect(verifyResult.status == 0)
        let verifyOutput = try decodeCommandOutput(verifyResult.stdout)
        #expect(verifyOutput.ok)
        #expect(verifyOutput.command == "manifest.verify")
        if case .array(let items)? = verifyOutput.data?["items"] {
            #expect(items.count == 2)
            for item in items {
                if case .object(let itemObject) = item {
                    #expect(itemObject["ok"] == .bool(true))
                } else {
                    Issue.record("Expected manifest.verify data.items to be objects.")
                }
            }
        } else {
            Issue.record("Expected manifest.verify data.items to be a JSON array.")
        }
    }

    @Test
    func cliExecUsageErrorsEmitStructuredJSON() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let latchkeydBin = repoRoot.appendingPathComponent(".build/debug/latchkeyd")
        let manifestURL = try temporaryDirectory().appendingPathComponent("manifest.json")

        let result = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["exec", "--manifest", manifestURL.path, "--policy", "example-demo"],
            environment: [:],
            currentDirectory: repoRoot
        )

        #expect(result.status == 2)
        let errorOutput = try decodeErrorOutput(result.stderr)
        #expect(!errorOutput.ok)
        #expect(errorOutput.error.code == "USAGE_ERROR")
        #expect(errorOutput.error.message.contains("requires --policy and --caller"))
    }

    @Test
    func wrapperHealthAndDiscoverAreCallable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let wrapper = repoRoot.appendingPathComponent("examples/bin/example-wrapper")

        let health = try runProcess(
            executable: "/bin/bash",
            arguments: [wrapper.path, "--health"],
            environment: [:]
        )
        #expect(health.status == 0)
        let healthOutput = try decodeWrapperOperationOutput(health.stdout)
        #expect(healthOutput.ok)
        #expect(healthOutput.connector == "example-wrapper")
        #expect(healthOutput.operation == "health")

        let discover = try runProcess(
            executable: "/bin/bash",
            arguments: [wrapper.path, "--discover"],
            environment: [:]
        )
        #expect(discover.status == 0)
        let discoverOutput = try decodeWrapperDiscoverOutput(discover.stdout)
        #expect(discoverOutput.ok)
        #expect(discoverOutput.connector == "example-wrapper")
        #expect(discoverOutput.commands.map(\.name) == ["demo"])
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeFixtureRepo(at root: URL) throws -> URL {
    let wrapperDir = root.appendingPathComponent("examples/bin", isDirectory: true)
    let secretsDir = root.appendingPathComponent("examples/file-backend", isDirectory: true)
    try FileManager.default.createDirectory(at: wrapperDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)

    let wrapper = wrapperDir.appendingPathComponent("example-wrapper")
    let binary = wrapperDir.appendingPathComponent("example-demo-cli")
    let secrets = secretsDir.appendingPathComponent("demo-secrets.json")

    try Data("#!/usr/bin/env bash\nexit 0\n".utf8).write(to: wrapper)
    try Data("#!/usr/bin/env bash\nif [ -z \"${LATCHKEYD_EXAMPLE_TOKEN:-}\" ]; then\n  exit 9\nfi\nexit 0\n".utf8).write(to: binary)
    try Data(#"{"example-token":"fixture-token"}"#.utf8).write(to: secrets)

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    return root
}

private func runProcess(
    executable: String,
    arguments: [String],
    environment: [String: String],
    currentDirectory: URL? = nil
) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.currentDirectoryURL = currentDirectory
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    return (
        process.terminationStatus,
        String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

private struct DemoCLIOutput: Decodable {
    let ok: Bool
    let tool: String
    let tokenPreview: String
    let tokenLength: Int
    let args: [String]
}

private struct WrapperOperationOutput: Decodable {
    let ok: Bool
    let connector: String
    let operation: String
    let message: String?
}

private struct WrapperDiscoverOutput: Decodable {
    struct Command: Decodable {
        let name: String
        let description: String
    }

    let ok: Bool
    let connector: String
    let commands: [Command]
    let contract: [String]
}

private func decodeCommandOutput(_ text: String) throws -> CommandOutput {
    try JSONDecoder().decode(CommandOutput.self, from: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
}

private func decodeErrorOutput(_ text: String) throws -> ErrorOutput {
    try JSONDecoder().decode(ErrorOutput.self, from: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
}

private func decodeDemoCLIOutput(_ text: String) throws -> DemoCLIOutput {
    try JSONDecoder().decode(DemoCLIOutput.self, from: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
}

private func decodeWrapperOperationOutput(_ text: String) throws -> WrapperOperationOutput {
    try JSONDecoder().decode(WrapperOperationOutput.self, from: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
}

private func decodeWrapperDiscoverOutput(_ text: String) throws -> WrapperDiscoverOutput {
    try JSONDecoder().decode(WrapperDiscoverOutput.self, from: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
}

private func decodeEventRecords(at url: URL) throws -> [EventRecord] {
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text
        .split(separator: "\n")
        .map { line in
            try JSONDecoder().decode(EventRecord.self, from: Data(line.utf8))
        }
}
