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
        let contents = try String(contentsOf: eventsURL, encoding: .utf8)
        #expect(contents.contains("\"result\":\"ok\""))
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

        let contents = try String(contentsOf: temp.appendingPathComponent("events.jsonl"), encoding: .utf8)
        #expect(contents.contains("\"result\":\"denied\""))
        #expect(contents.contains("\"reason\":\"trust_denied\""))
        #expect(!contents.contains("fixture-token"))
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

        let contents = try String(contentsOf: eventsURL, encoding: .utf8)
        #expect(contents.contains("\"result\":\"denied\""))
        #expect(contents.contains("\"reason\":\"backend_error\""))
    }

    @Test
    func keychainBackendAvailabilityCheckIsMacOSGated() throws {
        let backend = KeychainSecretBackend(servicePrefix: "latchkeyd", account: NSUserName())
        try backend.availabilityCheck()
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
        #expect(health.stdout.contains("\"ok\":true"))

        let discover = try runProcess(
            executable: "/bin/bash",
            arguments: [wrapper.path, "--discover"],
            environment: [:]
        )
        #expect(discover.status == 0)
        #expect(discover.stdout.contains("demo"))
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

private func runProcess(executable: String, arguments: [String], environment: [String: String]) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
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
