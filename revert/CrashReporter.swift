import Foundation
import Darwin

/// Installs the last-resort crash handlers and drops their reports into
/// `RideDebug/Reports/`, the same folder the debug screen lists.
///
/// Signal handlers cannot use Foundation safely, so they write a small
/// preformatted report to a fixed "Crash pending.txt" path. On the next launch
/// that file is promoted to a dated report. Objective-C exceptions run in a
/// normal context, so those are written with the full reason and call stack.
nonisolated enum CrashReporter {
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var crashPath: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var crashHeader: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigAbrt: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigSegv: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigBus: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigIll: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigFpe: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigTrap: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var sigOther: UnsafeMutablePointer<CChar>?
    /// An uncaught Objective-C exception writes a full report, then aborts into
    /// the signal handler; skip the pending signal file in that case so one
    /// crash does not become two reports.
    nonisolated(unsafe) private static var exceptionReported = false

    private static var pendingURL: URL {
        DebugReports.reportsDirectory.appendingPathComponent("Crash pending.txt")
    }

    static func install() {
        guard !installed else { return }
        installed = true

        try? FileManager.default.createDirectory(at: DebugReports.reportsDirectory,
                                                 withIntermediateDirectories: true)
        promotePendingCrash()

        NSSetUncaughtExceptionHandler(revertHandleException)

        crashPath = strdup(pendingURL.path)
        crashHeader = strdup(header())
        sigAbrt = strdup("Signal SIGABRT — abort() or an uncaught runtime failure.\n")
        sigSegv = strdup("Signal SIGSEGV — invalid memory access.\n")
        sigBus = strdup("Signal SIGBUS — bad memory access or alignment.\n")
        sigIll = strdup("Signal SIGILL — illegal instruction.\n")
        sigFpe = strdup("Signal SIGFPE — arithmetic exception.\n")
        sigTrap = strdup("Signal SIGTRAP — trap or fatal precondition.\n")
        sigOther = strdup("Signal — the app was terminated by a system signal.\n")

        for signalNumber in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(signalNumber, revertCrashSignal)
        }
    }

    /// Called from the C signal handler. Only preallocated strings and
    /// async-signal-safe POSIX calls are used here.
    static func markExceptionReported() {
        exceptionReported = true
    }

    static func handleSignal(_ signo: Int32) {
        if !exceptionReported, let crashPath {
            let fd = open(crashPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
            writeString(crashHeader, to: fd)
            switch signo {
            case SIGABRT: writeString(sigAbrt, to: fd)
            case SIGSEGV: writeString(sigSegv, to: fd)
            case SIGBUS: writeString(sigBus, to: fd)
            case SIGILL: writeString(sigIll, to: fd)
            case SIGFPE: writeString(sigFpe, to: fd)
            case SIGTRAP: writeString(sigTrap, to: fd)
            default: writeString(sigOther, to: fd)
            }
                close(fd)
            }
        }

        // Keep the normal crash behaviour (and the system crash report).
        signal(signo, SIG_DFL)
        raise(signo)
        _exit(1)
    }

    private static func writeString(_ pointer: UnsafeMutablePointer<CChar>?, to fd: Int32) {
        guard let pointer else { return }
        _ = write(fd, pointer, strlen(pointer))
    }

    private static func header() -> String {
        """
        REVERT CRASH REPORT
        App \(RevertDiagnostics.appVersion) (\(RevertDiagnostics.appBuild))  iOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Device \(deviceModel())

        The app terminated on a crash signal. This file is promoted to a dated
        report the next time Revert launches. The last ride debug file usually
        shows what the app was doing just before the crash.

        """
    }

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
        }
        return identifier.isEmpty ? "iPhone" : identifier
    }

    /// FileManager work, safe here because this runs at launch and after an
    /// Objective-C exception (not inside a signal handler).
    private static func promotePendingCrash() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: pendingURL.path) else { return }
        let values = try? pendingURL.resourceValues(forKeys: [.creationDateKey])
        let date = values?.creationDate ?? Date()
        let base = "\(DebugReports.fileStamp(date)) Crash — Signal crash"
        var destination = DebugReports.reportsDirectory.appendingPathComponent("\(base).txt")
        if fm.fileExists(atPath: destination.path) {
            destination = DebugReports.reportsDirectory
                .appendingPathComponent("\(base) \(UUID().uuidString.prefix(6)).txt")
        }
        do {
            try fm.moveItem(at: pendingURL, to: destination)
            if let handle = try? FileHandle(forWritingTo: destination) {
                let note = "\nPromoted \(Date().formatted(date: .complete, time: .standard)).\n"
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(note.utf8))
                try? handle.close()
            }
        } catch {
            // Leave the pending file in place; the debug screen can still show it.
        }
    }
}

private nonisolated func revertCrashSignal(_ signo: Int32) {
    CrashReporter.handleSignal(signo)
}

private nonisolated func revertHandleException(_ exception: NSException) {
    CrashReporter.markExceptionReported()
    let stack = exception.callStackSymbols.joined(separator: "\n")
    var body = """
    Exception: \(exception.name.rawValue)
    Reason: \(exception.reason ?? "—")
    Stack:
    \(stack)
    """
    let tail = RevertDiagnostics.text()
        .split(separator: "\n")
        .suffix(40)
        .joined(separator: "\n")
    if !tail.isEmpty {
        body += "\n\nRecent diagnostics:\n\(tail)"
    }
    DebugReports.write(kind: "Crash", title: "Exception \(exception.name.rawValue)", body: body)
}
