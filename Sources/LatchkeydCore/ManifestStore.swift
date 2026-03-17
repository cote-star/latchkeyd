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
            version: 2,
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
            operationSets: [
                "example-brokered-ops": OperationSet(
                    operations: [
                        OperationDefinition(
                            name: .secretResolve,
                            allowedSecrets: ["example-token"],
                            allowedResponseFields: ["secretName", "value", "lifetimeSeconds"]
                        )
                    ]
                )
            ],
            execPolicies: [
                "example-demo": ExecPolicy(
                    mode: .handoff,
                    wrapper: "example-wrapper",
                    binary: "example-cli",
                    secrets: ["example-token"],
                    description: "Reference policy for the public alpha example wrapper."
                ),
                "example-brokered": ExecPolicy(
                    mode: .brokered,
                    wrapper: "example-wrapper",
                    binary: "example-cli",
                    secrets: ["example-token"],
                    operationSet: "example-brokered-ops",
                    description: "Reference policy for the brokered example wrapper flow."
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
        guard manifest.version == 1 || manifest.version == 2 else {
            throw LatchkeydError.manifest("Unsupported manifest version \(manifest.version). Expected version 1 or 2.")
        }

        if manifest.version == 1 {
            try ensureLegacyOperationConstraints(manifest)
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

        if manifest.version == 2 {
            items.append(contentsOf: try validateOperationSets(manifest))
            items.append(contentsOf: try validatePolicies(manifest))
        }

        return items
    }

    private func ensureLegacyOperationConstraints(_ manifest: Manifest) throws {
        if manifest.operationSets != nil {
            throw LatchkeydError.manifest("Manifest version 1 may not declare operationSets.")
        }
        if manifest.execPolicies.values.contains(where: { $0.operationSet != nil }) {
            throw LatchkeydError.manifest("Manifest version 1 may not reference operationSet in execPolicies.")
        }
    }

    private func validateOperationSets(_ manifest: Manifest) throws -> [ValidationItem] {
        guard manifest.version == 2 else { return [] }
        guard let operationSets = manifest.operationSets, !operationSets.isEmpty else { return [] }

        var items: [ValidationItem] = []
        let secretNames = Set(manifest.secrets.keys)
        let allowedResponseFields = Set(["secretName", "value", "lifetimeSeconds"])

        for (name, set) in operationSets.sorted(by: { $0.key < $1.key }) {
            guard !set.operations.isEmpty else {
                throw LatchkeydError.manifest("Operation set '\(name)' must declare at least one operation.")
            }

            for operation in set.operations {
                guard !operation.allowedSecrets.isEmpty else {
                    throw LatchkeydError.manifest("Operation `\(operation.name.rawValue)` in set `\(name)` must allow at least one secret.")
                }
                for secretName in operation.allowedSecrets {
                    guard secretNames.contains(secretName) else {
                        throw LatchkeydError.manifest("Operation `\(operation.name.rawValue)` in set `\(name)` references unknown secret `\(secretName)`.")
                    }
                }
                if let responseFields = operation.allowedResponseFields {
                    guard Set(responseFields).isSubset(of: allowedResponseFields) else {
                        throw LatchkeydError.manifest("Operation `\(operation.name.rawValue)` in set `\(name)` declares unsupported response fields.")
                    }
                }
            }

            items.append(ValidationItem(name: "operationSet:\(name)", ok: true, message: "verified"))
        }

        return items
    }

    private func validatePolicies(_ manifest: Manifest) throws -> [ValidationItem] {
        guard manifest.version == 2 else { return [] }
        let operationSets = manifest.operationSets ?? [:]

        var items: [ValidationItem] = []
        for (name, policy) in manifest.execPolicies.sorted(by: { $0.key < $1.key }) {
            let itemName = "policy:\(name)"
            switch policy.mode {
            case .brokered:
                guard let operationSetName = policy.operationSet else {
                    throw LatchkeydError.manifest("Brokered policy `\(name)` requires an operationSet.")
                }
                guard let operationSet = operationSets[operationSetName] else {
                    throw LatchkeydError.manifest("Brokered policy `\(name)` references unknown operationSet `\(operationSetName)`.")
                }
                let allowedSecrets = Set(operationSet.operations.flatMap { $0.allowedSecrets })
                let policySecrets = Set(policy.secrets)
                guard !allowedSecrets.isDisjoint(with: policySecrets) else {
                    throw LatchkeydError.manifest("Brokered policy `\(name)` secrets do not intersect with operationSet `\(operationSetName)`.")
                }
                items.append(ValidationItem(name: itemName, ok: true, message: "operationSet `\(operationSetName)` verified"))
            default:
                guard policy.operationSet == nil else {
                    throw LatchkeydError.manifest("Policy `\(name)` may not declare an operationSet when mode is `\(policy.mode.rawValue)`.")
                }
                items.append(ValidationItem(name: itemName, ok: true, message: "mode `\(policy.mode.rawValue)`"))
            }
        }

        return items
    }
}
