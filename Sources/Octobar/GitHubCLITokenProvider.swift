import Foundation

enum GitHubCLITokenProvider {
    static func fetchToken() async -> String? {
        await Task.detached(priority: .utility) {
            fetchTokenSync()
        }.value
    }

    private static func fetchTokenSync() -> String? {
        for executable in ghExecutables() {
            if let token = runGHAuthToken(executable: executable) {
                return token
            }
        }

        return runGenericEnvAuthToken()
    }

    private static func ghExecutables() -> [String] {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]

        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runGHAuthToken(executable: String) -> String? {
        runProcess(executable: executable, arguments: ["auth", "token"])
    }

    private static func runGenericEnvAuthToken() -> String? {
        runProcess(executable: "/usr/bin/env", arguments: ["gh", "auth", "token"])
    }

    private static func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
