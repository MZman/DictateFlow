import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunner {
    static func run(executablePath: String, arguments: [String], input: String? = nil) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var stdinPipe: Pipe?
            if input != nil {
                let pipe = Pipe()
                stdinPipe = pipe
                process.standardInput = pipe
            }

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(
                    returning: ProcessResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()

                if let input, let stdinPipe {
                    let data = Data(input.utf8)
                    stdinPipe.fileHandleForWriting.write(data)
                    stdinPipe.fileHandleForWriting.closeFile()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
