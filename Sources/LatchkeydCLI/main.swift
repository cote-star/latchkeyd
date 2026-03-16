import Foundation
import LatchkeydCore

let cli = CLI()
exit(cli.run(arguments: Array(CommandLine.arguments.dropFirst())))
