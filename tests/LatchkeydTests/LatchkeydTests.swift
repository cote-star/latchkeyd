import Foundation
import Darwin
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
    func legacyManifestPolicyDefaultsToHandoffMode() throws {
        let temp = try temporaryDirectory()
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let manifestJSON = """
        {
          "version": 1,
          "backend": {
            "type": "file",
            "filePath": "/tmp/demo-secrets.json"
          },
          "wrappers": {
            "example-wrapper": {
              "path": "/tmp/example-wrapper",
              "sha256": "abc"
            }
          },
          "binaries": {
            "example-cli": {
              "path": "/tmp/example-cli",
              "sha256": "def"
            }
          },
          "secrets": {
            "example-token": {
              "envVar": "LATCHKEYD_EXAMPLE_TOKEN",
              "backendKey": "example-token"
            }
          },
          "execPolicies": {
            "example-demo": {
              "wrapper": "example-wrapper",
              "binary": "example-cli",
              "secrets": ["example-token"]
            }
          }
        }
        """
        try Data(manifestJSON.utf8).write(to: manifestURL)

        let store = ManifestStore(manifestURL: manifestURL, currentDirectory: temp)
        let manifest = try store.load()

        #expect(manifest.execPolicies["example-demo"]?.mode == .handoff)
    }

    @Test
    func manifestLoadRejectsUnknownPolicyMode() throws {
        let temp = try temporaryDirectory()
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let manifestJSON = """
        {
          "version": 1,
          "backend": {
            "type": "file",
            "filePath": "/tmp/demo-secrets.json"
          },
          "wrappers": {
            "example-wrapper": {
              "path": "/tmp/example-wrapper",
              "sha256": "abc"
            }
          },
          "binaries": {
            "example-cli": {
              "path": "/tmp/example-cli",
              "sha256": "def"
            }
          },
          "secrets": {
            "example-token": {
              "envVar": "LATCHKEYD_EXAMPLE_TOKEN",
              "backendKey": "example-token"
            }
          },
          "execPolicies": {
            "example-demo": {
              "mode": "banana",
              "wrapper": "example-wrapper",
              "binary": "example-cli",
              "secrets": ["example-token"]
            }
          }
        }
        """
        try Data(manifestJSON.utf8).write(to: manifestURL)

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

        #expect(manifest.version == 2)
        #expect(manifest.backend.type == .file)
        #expect(manifest.wrappers["example-wrapper"] != nil)
        #expect(manifest.binaries["example-cli"]?.lookupName == "example-demo-cli")
        #expect(manifest.operationSets?["example-brokered-ops"] != nil)
        #expect(manifest.execPolicies["example-brokered"]?.mode == .brokered)
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
    func manifestPoliciesDefaultToHandoffMode() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let store = ManifestStore(manifestURL: manifestURL, currentDirectory: repo)

        _ = try store.initialize(force: true)
        try updateManifestPolicy(at: manifestURL) { policy in
            policy.removeValue(forKey: "mode")
        }

        let manifest = try store.load()
        #expect(manifest.execPolicies["example-demo"]?.mode == .handoff)
    }

    @Test
    func manifestLoadRejectsUnknownMode() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let store = ManifestStore(manifestURL: manifestURL, currentDirectory: repo)

        _ = try store.initialize(force: true)
        try updateManifestPolicy(at: manifestURL) { policy in
            policy["mode"] = "invalid-mode"
        }

        #expect(throws: LatchkeydError.self) {
            _ = try store.load()
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
        #expect(events.first?.policyMode == "handoff")
        let contents = try String(contentsOf: eventsURL, encoding: .utf8)
        #expect(!contents.contains(secretValue))
    }

    @Test
    func oneshotPolicyAllowsBoundedExecArguments() throws {
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
                "example-demo": ExecPolicy(mode: .oneshot, wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
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
            ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: ["publish"])
        )

        #expect(status == 0)
        let events = try decodeEventRecords(at: eventsURL)
        #expect(events.count == 1)
        #expect(events.first?.result == "ok")
        #expect(events.first?.policyMode == "oneshot")
    }

    @Test
    func oneshotPolicyRejectsObviousLongLivedArguments() throws {
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
                "example-demo": ExecPolicy(mode: .oneshot, wrapper: "example-wrapper", binary: "example-cli", secrets: ["example-token"])
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

        do {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: ["--watch"])
            )
            Issue.record("Expected oneshot mode to reject obvious long-lived arguments.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "USAGE_ERROR")
            #expect(error.errorOutput.error.message.contains("oneshot mode"))
        }

        let events = try decodeEventRecords(at: eventsURL)
        #expect(events.count == 1)
        #expect(events.first?.result == "denied")
        #expect(events.first?.reason == "usage_error")
        #expect(events.first?.policyMode == "oneshot")
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
    func oneshotPolicyRejectsLongRunningArguments() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path
        let eventsURL = temp.appendingPathComponent("events.jsonl")

        let manifest = Manifest(
            version: 1,
            notes: ["policy:example-demo:mode=oneshot"],
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

        do {
            _ = try service.execute(
                ExecRequest(policyName: "example-demo", callerPath: wrapperPath, arguments: ["--watch"])
            )
            Issue.record("Expected oneshot policy to reject watch flag.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "USAGE_ERROR")
        }
    }

    @Test
    func oneshotPolicyExecutesBoundedCommand() throws {
        let temp = try temporaryDirectory()
        let repo = try makeFixtureRepo(at: temp)
        let wrapperPath = repo.appendingPathComponent("examples/bin/example-wrapper").path
        let binaryPath = repo.appendingPathComponent("examples/bin/example-demo-cli").path
        let secretsURL = repo.appendingPathComponent("examples/file-backend/demo-secrets.json").path
        let eventsURL = temp.appendingPathComponent("events.jsonl")

        let manifest = Manifest(
            version: 1,
            notes: ["policy:example-demo:mode=oneshot"],
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
        #expect(events.first?.result == "ok")
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
        #expect(statusOutput.data?["supportedModes"] == .array(ExecMode.allCases.map { .string($0.rawValue) }))
        #expect(statusOutput.data?["brokeredProtocolVersion"] == .int(1))

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
            #expect(items.count == 5)
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
    func demoCLIBrokeredSessionExercisesSecretResolve() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let demoCLI = repoRoot.appendingPathComponent("examples/bin/example-demo-cli")
        let socketDir = try temporaryDirectory()
        let socketPath = socketDir.appendingPathComponent("brokered.sock").path
        let listener = try UnixDomainSocketListener(path: socketPath)

        let serverReady = DispatchSemaphore(value: 0)
        let requestHandled = DispatchSemaphore(value: 0)
        var serverError: Error?

        DispatchQueue.global().async {
            serverReady.signal()
            do {
                let client = try listener.acceptConnection()
                defer { Darwin.close(client) }
                let requestLine = try listener.readLine(from: client)
                if let requestData = requestLine.data(using: .utf8),
                   let request = try JSONSerialization.jsonObject(with: requestData, options: []) as? [String: Any] {
                    #expect(request["operation"] as? String == "secret.resolve")
                    #expect(request["sessionId"] as? String == "session-123")
                    if let arguments = request["arguments"] as? [String: Any] {
                        #expect(arguments["secretName"] as? String == "example-token")
                    } else {
                        Issue.record("Expected broker request arguments to be present.")
                    }
                } else {
                    Issue.record("Expected broker request to be JSON.")
                }
                let response: [String: Any] = [
                    "ok": true,
                    "operation": "secret.resolve",
                    "data": [
                        "secretName": "example-token",
                        "value": "brokered-secret"
                    ]
                ]
                try listener.sendResponse(for: client, json: response)
            } catch {
                serverError = error
            }
            requestHandled.signal()
        }

        serverReady.wait()
        let brokeredArgs = ["smoke"]
        let result = try runProcess(
            executable: "/bin/bash",
            arguments: [demoCLI.path] + brokeredArgs,
            environment: [
                "LATCHKEYD_SESSION_SOCKET": socketPath,
                "LATCHKEYD_SESSION_ID": "session-123",
                "LATCHKEYD_SESSION_TOKEN": "session-token",
                "LATCHKEYD_POLICY_NAME": "example-demo",
                "LATCHKEYD_POLICY_MODE": "brokered",
            ]
        )

        requestHandled.wait()
        if result.status != 0 {
            Issue.record("demo CLI exit \(result.status). stdout: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        #expect(result.status == 0)
        #expect(serverError == nil)
        let output = try decodeDemoCLIOutput(result.stdout)
        #expect(output.ok)
        if let brokered = output.brokeredOperation {
            #expect(brokered.operation == "secret.resolve")
            #expect(brokered.secretName == "example-token")
            #expect(brokered.valueLength == 15)
        } else {
            Issue.record("Expected brokeredOperation block in demo CLI output.")
        }
        #expect(output.args == brokeredArgs)
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
        #expect(discoverOutput.commands.map(\.name) == ["demo", "brokered-demo"])
    }

    @Test
    func brokeredRawExecAndWrapperDemoResolveSecretThroughSession() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let latchkeydBin = repoRoot.appendingPathComponent(".build/debug/latchkeyd")
        let wrapper = repoRoot.appendingPathComponent("examples/bin/example-wrapper")
        let manifestURL = try temporaryDirectory().appendingPathComponent("manifest.json")

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

        let rawExec = try runProcess(
            executable: latchkeydBin.path,
            arguments: [
                "exec",
                "--manifest", manifestURL.path,
                "--policy", "example-brokered",
                "--caller", wrapper.path,
                "--", "smoke"
            ],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )
        #expect(rawExec.status == 0)
        let rawOutput = try decodeDemoCLIOutput(rawExec.stdout)
        #expect(rawOutput.ok)
        #expect(rawOutput.transport == "brokered")
        #expect(rawOutput.brokeredOperation?.operation == "secret.resolve")
        #expect(rawOutput.brokeredOperation?.policyMode == "brokered")
        #expect(rawOutput.args == ["smoke"])

        let wrapperExec = try runProcess(
            executable: "/bin/bash",
            arguments: [wrapper.path, "brokered-demo", "--manifest", manifestURL.path, "alpha"],
            environment: ["LATCHKEYD_BIN": latchkeydBin.path],
            currentDirectory: repoRoot
        )
        #expect(wrapperExec.status == 0)
        let wrapperOutput = try decodeDemoCLIOutput(wrapperExec.stdout)
        #expect(wrapperOutput.ok)
        #expect(wrapperOutput.transport == "brokered")
        #expect(wrapperOutput.brokeredOperation?.operation == "secret.resolve")
        #expect(wrapperOutput.args == ["alpha"])
    }

    @Test
    func brokeredExecRejectsUnsupportedOperation() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let latchkeydBin = repoRoot.appendingPathComponent(".build/debug/latchkeyd")
        let wrapper = repoRoot.appendingPathComponent("examples/bin/example-wrapper")
        let manifestURL = try temporaryDirectory().appendingPathComponent("manifest.json")

        let baseEnvironment = [
            "LATCHKEYD_BIN": latchkeydBin.path,
            "PATH": "\(repoRoot.appendingPathComponent("examples/bin").path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]

        _ = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "init", "--manifest", manifestURL.path, "--force"],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )
        _ = try runProcess(
            executable: latchkeydBin.path,
            arguments: ["manifest", "refresh", "--manifest", manifestURL.path],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )

        let result = try runProcess(
            executable: latchkeydBin.path,
            arguments: [
                "exec",
                "--manifest", manifestURL.path,
                "--policy", "example-brokered",
                "--caller", wrapper.path,
                "--", "--brokered-operation", "secret.invalid"
            ],
            environment: baseEnvironment,
            currentDirectory: repoRoot
        )

        #expect(result.status != 0)
        #expect(result.stdout.contains("OPERATION_NOT_ALLOWED"))
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

private func updateManifestPolicy(at manifestURL: URL, transform: (inout [String: Any]) -> Void) throws {
    let data = try Data(contentsOf: manifestURL)
    var json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    guard var execPolicies = json["execPolicies"] as? [String: Any],
          var policy = execPolicies["example-demo"] as? [String: Any] else {
        fatalError("Expected manifest execPolicies entry for example-demo")
    }
    transform(&policy)
    execPolicies["example-demo"] = policy
    json["execPolicies"] = execPolicies
    let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try updated.write(to: manifestURL)
}

private final class UnixDomainSocketListener {
    let path: String
    private let listeningFD: Int32

    init(path: String) throws {
        self.path = path
        listeningFD = Darwin.socket(AF_UNIX, Int32(SOCK_STREAM), 0)
        guard listeningFD >= 0 else {
            throw posixError(errno)
        }
        _ = Darwin.unlink(path)

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { cstr in
            let maxBytes = MemoryLayout.size(ofValue: addr.sun_path) - 1
            strncpy(&addr.sun_path.0, cstr, maxBytes)
        }

        var addrCopy = addr
        let addressLength = socklen_t(addrCopy.sun_len)
        let bindResult = withUnsafePointer(to: &addrCopy) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listeningFD, sockPtr, addressLength)
            }
        }
        guard bindResult >= 0 else {
            Darwin.close(listeningFD)
            throw posixError(errno)
        }

        guard listen(listeningFD, 1) >= 0 else {
            Darwin.close(listeningFD)
            throw posixError(errno)
        }
    }

    func acceptConnection() throws -> Int32 {
        let client = Darwin.accept(listeningFD, nil, nil)
        guard client >= 0 else {
            throw posixError(errno)
        }
        return client
    }

    func readLine(from fd: Int32) throws -> String {
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let bytesRead = Darwin.read(fd, &byte, 1)
            if bytesRead <= 0 {
                break
            }
            if byte == 0x0a {
                break
            }
            buffer.append(byte)
        }
        guard let line = String(data: buffer, encoding: .utf8) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EILSEQ), userInfo: nil)
        }
        return line
    }

    func sendResponse(for fd: Int32, json: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: json, options: [])
        data.append(0x0a)
        try data.withUnsafeBytes { ptr in
            var written = 0
            while written < ptr.count {
                let chunk = Darwin.write(fd, ptr.baseAddress!.advanced(by: written), ptr.count - written)
                if chunk <= 0 {
                    throw posixError(errno)
                }
                written += chunk
            }
        }
    }

    deinit {
        Darwin.close(listeningFD)
        _ = Darwin.unlink(path)
    }
}

extension UnixDomainSocketListener: @unchecked Sendable {}

private func posixError(_ code: Int32) -> Error {
    NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil)
}

private struct DemoCLIOutput: Decodable {
    let ok: Bool
    let tool: String
    let transport: String?
    let tokenPreview: String?
    let tokenLength: Int?
    let args: [String]
    let brokeredOperation: BrokeredOperation?
}

private struct BrokeredOperation: Decodable {
    let operation: String
    let secretName: String
    let valuePreview: String
    let valueLength: Int
    let policyName: String
    let policyMode: String
    let sessionId: String?
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
