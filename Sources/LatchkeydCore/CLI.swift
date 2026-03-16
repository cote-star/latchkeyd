import Foundation

public struct CLI {
    private let context: CLIContext

    public init(context: CLIContext = CLIContext()) {
        self.context = context
    }

    public func run(arguments: [String]) -> Int32 {
        do {
            let appPaths = try AppPaths.resolve(fileManager: context.fileManager)
            let parsed = try ParsedCommand(arguments: arguments, appPaths: appPaths, currentDirectory: context.currentDirectory)
            let manifestStore = ManifestStore(manifestURL: parsed.manifestURL, currentDirectory: context.currentDirectory)
            let logger = EventLogger(eventsURL: appPaths.eventsURL)

            switch parsed.command {
            case .status:
                let output = CommandOutput(
                    ok: true,
                    command: "status",
                    message: "latchkeyd is ready.",
                    data: [
                        "version": .string(latchkeydVersion),
                        "manifestPath": .string(parsed.manifestURL.path),
                        "supportDirectory": .string(appPaths.supportDirectory.path),
                        "eventsPath": .string(appPaths.eventsURL.path)
                    ]
                )
                try writeJSON(output, to: context.standardOutput)
                return 0

            case .manifestInit(let force):
                let manifest = try manifestStore.initialize(force: force)
                logger.log(command: "manifest.init", result: "ok", backendType: manifest.backend.type)
                let output = CommandOutput(
                    ok: true,
                    command: "manifest.init",
                    message: "Starter manifest written.",
                    data: [
                        "manifestPath": .string(parsed.manifestURL.path),
                        "backendType": .string(manifest.backend.type.rawValue)
                    ]
                )
                try writeJSON(output, to: context.standardOutput)
                return 0

            case .manifestRefresh:
                let manifest = try manifestStore.refresh()
                logger.log(command: "manifest.refresh", result: "ok", backendType: manifest.backend.type)
                let output = CommandOutput(
                    ok: true,
                    command: "manifest.refresh",
                    message: "Manifest hashes refreshed.",
                    data: [
                        "manifestPath": .string(parsed.manifestURL.path),
                        "wrapperCount": .int(manifest.wrappers.count),
                        "binaryCount": .int(manifest.binaries.count)
                    ]
                )
                try writeJSON(output, to: context.standardOutput)
                return 0

            case .manifestVerify:
                let items = try manifestStore.verify()
                let manifest = try manifestStore.load()
                logger.log(command: "manifest.verify", result: "ok", backendType: manifest.backend.type)
                let output = CommandOutput(
                    ok: true,
                    command: "manifest.verify",
                    message: "Manifest trust entries verified.",
                    data: [
                        "items": .array(items.map { .object(["name": .string($0.name), "message": .string($0.message), "ok": .bool($0.ok)]) })
                    ]
                )
                try writeJSON(output, to: context.standardOutput)
                return 0

            case .exec(let request):
                let manifest = try manifestStore.load()
                let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
                try backend.availabilityCheck()
                let broker = BrokerService(manifest: manifest, backend: backend, logger: logger, environment: context.environment)
                let code = try broker.execute(request)
                return code

            case .validate:
                let manifest = try manifestStore.load()
                let backend = try SecretBackendFactory.makeBackend(config: manifest.backend)
                try backend.availabilityCheck()
                let validator = Validator(
                    manifestURL: parsed.manifestURL,
                    manifestStore: manifestStore,
                    environment: context.environment,
                    logger: logger
                )
                let results = try validator.run(selfExecutablePath: CommandLine.arguments[0])
                let output = CommandOutput(
                    ok: true,
                    command: "validate",
                    message: "Validation succeeded.",
                    data: [
                        "items": .array(results.map { .object(["name": .string($0.name), "message": .string($0.message), "ok": .bool($0.ok)]) })
                    ]
                )
                try writeJSON(output, to: context.standardOutput)
                return 0
            }
        } catch let error as LatchkeydError {
            try? writeJSON(error.errorOutput, to: context.standardError)
            return error.exitCode
        } catch {
            try? writeJSON(ErrorOutput(code: "UNEXPECTED_ERROR", message: error.localizedDescription), to: context.standardError)
            return 99
        }
    }
}

public enum ParsedSubcommand {
    case status
    case manifestInit(force: Bool)
    case manifestRefresh
    case manifestVerify
    case exec(ExecRequest)
    case validate
}

public struct ParsedCommand {
    public let command: ParsedSubcommand
    public let manifestURL: URL

    public init(arguments: [String], appPaths: AppPaths, currentDirectory: URL) throws {
        guard let first = arguments.first else {
            throw LatchkeydError.usage(usageText())
        }

        var remaining = Array(arguments.dropFirst())
        var manifestURL = appPaths.manifestURL

        extractManifestURL(from: &remaining, currentDirectory: currentDirectory, into: &manifestURL)

        switch first {
        case "status":
            self.command = .status
        case "manifest":
            guard let subcommand = remaining.first else {
                throw LatchkeydError.usage(usageText())
            }
            let tail = Array(remaining.dropFirst())
            switch subcommand {
            case "init":
                self.command = .manifestInit(force: tail.contains("--force"))
            case "refresh":
                self.command = .manifestRefresh
            case "verify":
                self.command = .manifestVerify
            default:
                throw LatchkeydError.usage(usageText())
            }
        case "exec":
            var policyName: String?
            var callerPath: String?
            var execArguments: [String] = []
            var iterator = remaining.makeIterator()
            while let argument = iterator.next() {
                switch argument {
                case "--policy":
                    policyName = iterator.next()
                case "--caller":
                    callerPath = iterator.next()
                case "--":
                    execArguments = Array(iterator)
                default:
                    throw LatchkeydError.usage("Unknown exec argument `\(argument)`.\n\n\(usageText())")
                }
            }
            guard let policyName, let callerPath else {
                throw LatchkeydError.usage("`exec` requires --policy and --caller.\n\n\(usageText())")
            }
            self.command = .exec(ExecRequest(policyName: policyName, callerPath: callerPath, arguments: execArguments))
        case "validate":
            self.command = .validate
        case "--help", "-h", "help":
            throw LatchkeydError.usage(usageText())
        default:
            throw LatchkeydError.usage(usageText())
        }

        self.manifestURL = manifestURL
    }
}

private func extractManifestURL(from arguments: inout [String], currentDirectory: URL, into manifestURL: inout URL) {
    var index = 0
    while index < arguments.count {
        if arguments[index] == "--" {
            break
        }
        if arguments[index] == "--manifest" {
            if index + 1 >= arguments.count {
                break
            }
            let value = arguments[index + 1]
            manifestURL = URL(fileURLWithPath: canonicalPath(value, relativeTo: currentDirectory))
            arguments.removeSubrange(index...(index + 1))
            continue
        }
        index += 1
    }
}

public func usageText() -> String {
    """
    Usage:
      latchkeyd status [--manifest PATH]
      latchkeyd manifest init [--manifest PATH] [--force]
      latchkeyd manifest refresh [--manifest PATH]
      latchkeyd manifest verify [--manifest PATH]
      latchkeyd exec [--manifest PATH] --policy NAME --caller PATH [-- ARG...]
      latchkeyd validate [--manifest PATH]

    Notes:
      - The default manifest path is in the user's Application Support directory.
      - `exec` verifies the trusted wrapper path, trusted binary path/hash, and allowed secrets before launch.
      - The public alpha ships two backends: keychain and file.
    """
}
