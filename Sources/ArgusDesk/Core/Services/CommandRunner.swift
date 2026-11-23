import Darwin
import Foundation

/// Runs external system commands with captured output and a timeout.
///
/// Used for local ping, local HTTP checks, and key-only SSH. It intentionally
/// does not invoke a shell locally, so arguments are passed directly to the
/// executable.
struct CommandRunner {
    /// Executes a command and returns stdout, stderr, and the exit code.
    ///
    /// This method blocks the current thread until the command exits or times
    /// out, so callers should run it away from the main actor.
    func run(executable: String, arguments: [String], timeoutSeconds: TimeInterval) -> CommandResult {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
            defer { try? fileManager.removeItem(at: outputDirectory) }

            // Regular files let the child write both streams without waiting for a pipe reader.
            let stdoutURL = outputDirectory.appendingPathComponent("stdout")
            let stderrURL = outputDirectory.appendingPathComponent("stderr")
            try Data().write(to: stdoutURL)
            try Data().write(to: stderrURL)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            defer { try? stdout.close() }
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer { try? stderr.close() }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()

            let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            let timedOut = process.isRunning
            if timedOut {
                process.terminate()

                let stopDeadline = ProcessInfo.processInfo.systemUptime + 0.5
                while process.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }

                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }

            process.waitUntilExit()

            return CommandResult(
                exitCode: timedOut ? -1 : process.terminationStatus,
                stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
                stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self),
                timedOut: timedOut
            )
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }
    }
}

/// Captured command result.
struct CommandResult {
    /// Process termination code, or `-1` when the command did not launch or timed out.
    let exitCode: Int32

    /// Captured standard output.
    let stdout: String

    /// Captured standard error.
    let stderr: String

    /// Whether ArgusDesk stopped the command because it exceeded its timeout.
    let timedOut: Bool

    /// True when the command exited successfully before the timeout.
    var succeeded: Bool {
        exitCode == 0 && !timedOut
    }
}
