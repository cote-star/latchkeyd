import Foundation
import Testing
@testable import LatchkeydCore

struct KeychainSecretBackendTests {
    @Test
    func keychainResolveSecretReadsFromIsolatedTemporaryKeychain() throws {
        let tempDir = try FileManager.default.createTemporaryDirectory(named: "latchkeyd-keychain-test")
        let keychainURL = tempDir.appendingPathComponent("integration.keychain-db")
        let keychainPassword = "pw-\(UUID().uuidString)"
        let account = "acct-\(UUID().uuidString)"
        let backendKey = "secret-\(UUID().uuidString)"
        let service = "latchkeyd/\(backendKey)"
        let secretValue = "fixture-\(UUID().uuidString)"

        _ = try runSecurity(arguments: ["create-keychain", "-p", keychainPassword, keychainURL.path], allowedExitStatus: 0)
        defer {
            _ = try? runSecurity(arguments: ["delete-keychain", keychainURL.path], allowedExitStatus: 0)
            try? FileManager.default.removeItem(at: tempDir)
        }

        _ = try runSecurity(arguments: ["unlock-keychain", "-p", keychainPassword, keychainURL.path], allowedExitStatus: 0)
        _ = try runSecurity(
            arguments: ["add-generic-password", "-a", account, "-s", service, "-w", secretValue, keychainURL.path],
            allowedExitStatus: 0
        )

        let backend = KeychainSecretBackend(
            servicePrefix: "latchkeyd",
            account: account,
            runSecurityCommand: { account, service in
                let result = try runSecurity(
                    arguments: ["find-generic-password", "-a", account, "-s", service, "-w", keychainURL.path],
                    allowedExitStatus: nil
                )
                return SecurityCommandResult(
                    terminationStatus: result.status,
                    standardOutput: result.stdout,
                    standardError: result.stderr
                )
            }
        )

        let value = try backend.resolveSecret(
            spec: SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: backendKey)
        )

        #expect(value == secretValue)
    }

    @Test
    func keychainResolveSecretUsesTrimmedStdoutFromSecurityCommand() throws {
        var recordedAccount: String?
        var recordedService: String?
        let backend = KeychainSecretBackend(
            servicePrefix: "latchkeyd",
            account: "alice",
            runSecurityCommand: { account, service in
                recordedAccount = account
                recordedService = service
                return SecurityCommandResult(
                    terminationStatus: 0,
                    standardOutput: "  fixture-token \n",
                    standardError: ""
                )
            }
        )

        let value = try backend.resolveSecret(
            spec: SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
        )

        #expect(value == "fixture-token")
        #expect(recordedAccount == "alice")
        #expect(recordedService == "latchkeyd/example-token")
    }

    @Test
    func keychainResolveSecretSurfacesTrimmedSecurityErrorMessage() throws {
        let backend = KeychainSecretBackend(
            servicePrefix: "latchkeyd",
            account: "alice",
            runSecurityCommand: { _, _ in
                SecurityCommandResult(
                    terminationStatus: 51,
                    standardOutput: "",
                    standardError: " user interaction is not allowed. \n"
                )
            }
        )

        do {
            _ = try backend.resolveSecret(
                spec: SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            )
            Issue.record("Expected backend error for non-zero security exit status.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "BACKEND_ERROR")
            #expect(error.errorOutput.error.message.contains("latchkeyd/example-token"))
            #expect(error.errorOutput.error.message.contains("user interaction is not allowed."))
        }
    }

    @Test
    func keychainResolveSecretRejectsEmptySecurityStdout() throws {
        let backend = KeychainSecretBackend(
            servicePrefix: "latchkeyd",
            account: "alice",
            runSecurityCommand: { _, _ in
                SecurityCommandResult(
                    terminationStatus: 0,
                    standardOutput: "   \n",
                    standardError: ""
                )
            }
        )

        do {
            _ = try backend.resolveSecret(
                spec: SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            )
            Issue.record("Expected backend error for empty security output.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "BACKEND_ERROR")
            #expect(error.errorOutput.error.message.contains("returned an empty value"))
        }
    }

    @Test
    func keychainResolveSecretSurfacesSecurityInvocationFailures() throws {
        enum FakeRunnerError: LocalizedError {
            case launchFailure

            var errorDescription: String? {
                "unable to launch security"
            }
        }

        let backend = KeychainSecretBackend(
            servicePrefix: "latchkeyd",
            account: "alice",
            runSecurityCommand: { _, _ in
                throw FakeRunnerError.launchFailure
            }
        )

        do {
            _ = try backend.resolveSecret(
                spec: SecretSpec(envVar: "LATCHKEYD_EXAMPLE_TOKEN", backendKey: "example-token")
            )
            Issue.record("Expected backend error when security invocation fails.")
        } catch let error as LatchkeydError {
            #expect(error.errorOutput.error.code == "BACKEND_ERROR")
            #expect(error.errorOutput.error.message.contains("unable to launch security"))
        }
    }
}

private struct SecurityResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runSecurity(arguments: [String], allowedExitStatus: Int32?) throws -> SecurityResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let result = SecurityResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)

    if let allowedExitStatus, result.status != allowedExitStatus {
        throw NSError(
            domain: "KeychainSecretBackendTests",
            code: Int(result.status),
            userInfo: [
                NSLocalizedDescriptionKey: "security \(arguments.joined(separator: " ")) failed with exit \(result.status): \(stderr)"
            ]
        )
    }

    return result
}

private extension FileManager {
    func createTemporaryDirectory(named prefix: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
