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
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false
            )
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()

            let stopDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < stopDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            exitCode: timedOut ? -1 : Int32(process.terminationStatus),
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            timedOut: timedOut
        )
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
