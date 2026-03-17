import Foundation

public struct Validator {
    private let manifestURL: URL
    private let manifestStore: ManifestStore
    private let environment: [String: String]
    private let logger: EventLogger

    public init(manifestURL: URL, manifestStore: ManifestStore, environment: [String: String], logger: EventLogger) {
        self.manifestURL = manifestURL
        self.manifestStore = manifestStore
        self.environment = environment
        self.logger = logger
    }

    public func run(selfExecutablePath: String) throws -> [ValidationItem] {
        var results: [ValidationItem] = []
        try logger.prepare()
        let manifest = try manifestStore.load()
        let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)

        results.append(ValidationItem(name: "manifest:load", ok: true, message: "loaded"))
        results.append(contentsOf: try manifestStore.verify())

        try backend.availabilityCheck()
        results.append(ValidationItem(name: "backend:\(backend.type.rawValue)", ok: true, message: "available"))

        try runWrapperHealthCheck(manifest: manifest)
        results.append(ValidationItem(name: "example-wrapper:health", ok: true, message: "healthy"))

        try runWrapperDemo(manifest: manifest)
        results.append(ValidationItem(name: "example-wrapper:demo", ok: true, message: "demo succeeded"))

        try runDeniedScenario(selfExecutablePath: selfExecutablePath)
        results.append(ValidationItem(name: "denial:untrusted-caller", ok: true, message: "denial confirmed"))

        try logger.log(command: "validate", result: "ok", backendType: backend.type)
        return results
    }

    private func runWrapperHealthCheck(manifest: Manifest) throws {
        guard let wrapper = manifest.wrappers["example-wrapper"] else {
            throw LatchkeydError.manifest("Validation requires the `example-wrapper` manifest entry.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [canonicalPath(wrapper.path), "--health"]
        process.environment = environment.merging(["LATCHKEYD_BIN": canonicalPath(selfExecutablePath())]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LatchkeydError.execution("Example wrapper health check failed.", process.terminationStatus)
        }
    }

    private func runWrapperDemo(manifest: Manifest) throws {
        guard let wrapper = manifest.wrappers["example-wrapper"] else {
            throw LatchkeydError.manifest("Validation requires the `example-wrapper` manifest entry.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [canonicalPath(wrapper.path), "demo", "--manifest", manifestURL.path]
        process.environment = environment.merging(["LATCHKEYD_BIN": canonicalPath(selfExecutablePath())]) { _, new in new }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LatchkeydError.execution("Example wrapper demo failed.", process.terminationStatus)
        }
    }

    private func runDeniedScenario(selfExecutablePath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: selfExecutablePath)
        process.arguments = ["exec", "--manifest", manifestURL.path, "--policy", "example-demo", "--caller", "/tmp/not-trusted-wrapper.sh"]
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else {
            throw LatchkeydError.execution("Denied validation scenario unexpectedly succeeded.", process.terminationStatus)
        }
        let stderrText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard stderrText.contains("TRUST_DENIED") || stderrText.contains("path mismatch") else {
            throw LatchkeydError.execution("Denied validation scenario returned the wrong failure shape.", process.terminationStatus)
        }
    }

    private func selfExecutablePath() -> String {
        ProcessInfo.processInfo.environment["LATCHKEYD_BIN"] ?? CommandLine.arguments[0]
    }
}
