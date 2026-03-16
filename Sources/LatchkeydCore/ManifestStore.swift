import Foundation

public struct ManifestStore {
    public let manifestURL: URL
    public let currentDirectory: URL

    public init(manifestURL: URL, currentDirectory: URL) {
        self.manifestURL = manifestURL
        self.currentDirectory = currentDirectory
    }

    public func load() throws -> Manifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LatchkeydError.manifest("Manifest not found at \(manifestURL.path). Run `latchkeyd manifest init` first.")
        }
        return try decodeManifest(from: manifestURL)
    }

    public func save(_ manifest: Manifest) throws {
        try writeManifest(manifest, to: manifestURL)
    }

    public func initialize(force: Bool) throws -> Manifest {
        if FileManager.default.fileExists(atPath: manifestURL.path), !force {
            throw LatchkeydError.io("Manifest already exists at \(manifestURL.path). Re-run with --force to overwrite it.")
        }

        let wrapperPath = canonicalPath("examples/bin/example-wrapper", relativeTo: currentDirectory)
        let binaryPath = canonicalPath("examples/bin/example-demo-cli", relativeTo: currentDirectory)
        let fileBackendPath = canonicalPath("examples/file-backend/demo-secrets.json", relativeTo: currentDirectory)

        let manifest = Manifest(
            version: 1,
            notes: [
                "This starter manifest is designed for the repository example flow.",
                "The file backend is convenient for demos and CI. Prefer the keychain backend for real workstation use."
            ],
            backend: SecretBackendConfig(type: .file, filePath: fileBackendPath),
            wrappers: [
                "example-wrapper": TrustedPath(path: wrapperPath, sha256: try sha256(forFileAtPath: wrapperPath))
            ],
            binaries: [
                "example-cli": TrustedBinary(
                    path: binaryPath,
                    sha256: try sha256(forFileAtPath: binaryPath),
                    lookupName: "example-demo-cli"
                )
            ],
            secrets: [
                "example-token": SecretSpec(
                    envVar: "LATCHKEYD_EXAMPLE_TOKEN",
                    backendKey: "example-token",
                    description: "Harmless demo token for the reference wrapper flow."
                )
            ],
            execPolicies: [
                "example-demo": ExecPolicy(
                    wrapper: "example-wrapper",
                    binary: "example-cli",
                    secrets: ["example-token"],
                    description: "Reference policy for the public alpha example wrapper."
                )
            ]
        )
        try save(manifest)
        return manifest
    }

    public func refresh() throws -> Manifest {
        var manifest = try load()
        manifest.wrappers = try manifest.wrappers.mapValues { item in
            let path = canonicalPath(item.path)
            guard fileExists(path) else {
                throw LatchkeydError.io("Trusted wrapper path does not exist: \(path)")
            }
            return TrustedPath(path: path, sha256: try sha256(forFileAtPath: path))
        }

        manifest.binaries = try manifest.binaries.mapValues { item in
            let path = canonicalPath(item.path)
            guard fileExists(path) else {
                throw LatchkeydError.io("Trusted binary path does not exist: \(path)")
            }
            return TrustedBinary(path: path, sha256: try sha256(forFileAtPath: path), lookupName: item.lookupName)
        }

        try save(manifest)
        return manifest
    }

    public func verify() throws -> [ValidationItem] {
        let manifest = try load()
        guard manifest.version == 1 else {
            throw LatchkeydError.manifest("Unsupported manifest version \(manifest.version). Expected version 1.")
        }

        var items: [ValidationItem] = []

        for (name, wrapper) in manifest.wrappers.sorted(by: { $0.key < $1.key }) {
            let path = canonicalPath(wrapper.path)
            guard fileExists(path) else {
                throw LatchkeydError.trust(
                    "Trusted wrapper is missing: \(path)",
                    ["entry": .string(name), "path": .string(path), "kind": .string("wrapper")]
                )
            }
            let digest = try sha256(forFileAtPath: path)
            guard digest == wrapper.sha256 else {
                throw LatchkeydError.trust(
                    "Trusted wrapper hash mismatch for \(name).",
                    ["entry": .string(name), "path": .string(path), "kind": .string("wrapper")]
                )
            }
            items.append(ValidationItem(name: "wrapper:\(name)", ok: true, message: "verified"))
        }

        for (name, binary) in manifest.binaries.sorted(by: { $0.key < $1.key }) {
            let path = canonicalPath(binary.path)
            guard fileExists(path) else {
                throw LatchkeydError.trust(
                    "Trusted binary is missing: \(path)",
                    ["entry": .string(name), "path": .string(path), "kind": .string("binary")]
                )
            }
            let digest = try sha256(forFileAtPath: path)
            guard digest == binary.sha256 else {
                throw LatchkeydError.trust(
                    "Trusted binary hash mismatch for \(name).",
                    ["entry": .string(name), "path": .string(path), "kind": .string("binary")]
                )
            }
            items.append(ValidationItem(name: "binary:\(name)", ok: true, message: "verified"))
        }

        return items
    }
}
