#if canImport(UIKit)
import Darwin
import Foundation
import MachO
import UIKit

/// Details of a session that ended in a crash, recovered on the next launch.
struct CrashRecovery: Sendable {
    let videoURL: URL?
    let crashLogURL: URL
    var savedToPhotos: Bool
}

/// Persists a session marker, captures crash logs and recovers them on the next launch.
///
/// A crash handler can't finish a video or talk to Photos, so the recording is written as a
/// fragmented MP4 (playable even if never finalized) and recovered after relaunch.
enum CrashReporter {
    private struct Marker: Codable {
        var videoFileName: String?
        var savedToPhotos: Bool
    }

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BuildBarber", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var markerURL: URL { directory.appendingPathComponent("session.json") }
    private static var crashLogURL: URL { directory.appendingPathComponent("crash.log") }

    // Handlers can only read C globals, so the log path is kept as a C string.
    nonisolated(unsafe) private static var logPathC: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var headerC: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var previousExceptionHandler: (@convention(c) (NSException) -> Void)?
    nonisolated(unsafe) private static var previousActions: [Int32: sigaction] = [:]
    nonisolated(unsafe) private static var installed = false
    private static let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    static func videoURL(fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    // MARK: Session marker

    static func beginSession(videoFileName: String?) {
        try? FileManager.default.removeItem(at: crashLogURL)
        write(Marker(videoFileName: videoFileName, savedToPhotos: false))
        install()
    }

    static func markSavedToPhotos() {
        guard var marker = readMarker() else { return }
        marker.savedToPhotos = true
        write(marker)
    }

    static func endSession() {
        if let name = readMarker()?.videoFileName {
            try? FileManager.default.removeItem(at: videoURL(fileName: name))
        }
        try? FileManager.default.removeItem(at: markerURL)
        try? FileManager.default.removeItem(at: crashLogURL)
    }

    /// Returns the previous session's artifacts if it ended in a crash; otherwise cleans up any leftovers.
    static func recoverCrashedSession() -> CrashRecovery? {
        guard let marker = readMarker() else {
            try? FileManager.default.removeItem(at: crashLogURL)
            return nil
        }
        guard FileManager.default.fileExists(atPath: crashLogURL.path) else {
            endSession()
            return nil
        }
        var video = marker.videoFileName.map(videoURL(fileName:))
        if let url = video, RecordingLimits.fileSize(at: url) == 0 { video = nil }
        return CrashRecovery(videoURL: video, crashLogURL: crashLogURL, savedToPhotos: marker.savedToPhotos)
    }

    private static func readMarker() -> Marker? {
        (try? Data(contentsOf: markerURL)).flatMap { try? JSONDecoder().decode(Marker.self, from: $0) }
    }

    private static func write(_ marker: Marker) {
        if let data = try? JSONEncoder().encode(marker) { try? data.write(to: markerURL, options: .atomic) }
    }

    // MARK: Handlers

    private static func install() {
        guard !installed else { return }
        installed = true
        logPathC = strdup(crashLogURL.path)
        headerC = strdup(buildHeader())

        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.writeExceptionLog(exception)
            CrashReporter.previousExceptionHandler?(exception)
        }

        for sig in signals {
            var action = sigaction()
            var old = sigaction()
            action.__sigaction_u.__sa_sigaction = { sig, _, _ in CrashReporter.handleSignal(sig) }
            action.sa_flags = SA_SIGINFO
            sigemptyset(&action.sa_mask)
            if sigaction(sig, &action, &old) == 0 { previousActions[sig] = old }
        }
    }

    /// Metadata a server needs to symbolicate the log: build info and each non-system image's UUID and load address.
    private static func buildHeader() -> String {
        let info = Bundle.main.infoDictionary
        var lines = [
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "Version: \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))",
            "OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "Date: \(Date())",
            "Binary Images:"
        ]
        for i in 0..<_dyld_image_count() {
            guard let namePtr = _dyld_get_image_name(i), let header = _dyld_get_image_header(i) else { continue }
            let path = String(cString: namePtr)
            if path.hasPrefix("/usr/") || path.hasPrefix("/System/") || path.hasPrefix("/Library/") { continue }
            guard let uuid = imageUUID(header) else { continue }
            let name = (path as NSString).lastPathComponent
            lines.append("  \(String(format: "0x%llx", UInt64(UInt(bitPattern: header)))) \(uuid) \(name)")
        }
        if let appImage = mainExecutableImage(),
           !lines.contains(where: { $0.localizedCaseInsensitiveContains(appImage.uuid) }) {
            lines.append("  \(String(format: "0x%llx", appImage.address)) \(appImage.uuid) \(appImage.name)")
        }
        return lines.joined(separator: "\n") + "\n\n"
    }

    private static func imageUUID(_ header: UnsafePointer<mach_header>) -> String? {
        guard header.pointee.magic == MH_MAGIC_64 else { return nil }
        var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let cmd = cursor.load(as: load_command.self)
            guard cmd.cmdsize >= MemoryLayout<load_command>.size else { return nil }
            if cmd.cmd == UInt32(LC_UUID) {
                guard cmd.cmdsize >= MemoryLayout<uuid_command>.size else { return nil }
                let uuid = cursor.load(as: uuid_command.self).uuid
                return UUID(uuid: uuid).uuidString
            }
            cursor = cursor.advanced(by: Int(cmd.cmdsize))
        }
        return nil
    }

    private static func mainExecutableImage() -> (uuid: String, address: UInt64, name: String)? {
        guard let executablePath = Bundle.main.executableURL?.standardizedFileURL.path else { return nil }
        for i in 0..<_dyld_image_count() {
            guard let namePtr = _dyld_get_image_name(i), let header = _dyld_get_image_header(i) else { continue }
            let path = String(cString: namePtr)
            if URL(fileURLWithPath: path).standardizedFileURL.path == executablePath,
               let uuid = imageUUID(header) {
                return (uuid, UInt64(UInt(bitPattern: header)), (path as NSString).lastPathComponent)
            }
        }
        return nil
    }

    private static func writeExceptionLog(_ exception: NSException) {
        var text = buildHeader()
        text += "Uncaught exception: \(exception.name.rawValue)\n"
        text += "Reason: \(exception.reason ?? "none")\n"
        text += "Date: \(Date())\n\nCall stack:\n"
        text += exception.callStackSymbols.joined(separator: "\n")
        try? text.write(to: crashLogURL, atomically: true, encoding: .utf8)
    }

    private static func handleSignal(_ sig: Int32) {
        if let path = logPathC {
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                if let header = headerC { _ = Darwin.write(fd, header, strlen(header)) }
                let title = "Fatal signal: \(sig)\n\nCall stack:\n"
                _ = title.withCString { Darwin.write(fd, $0, strlen($0)) }
                var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
                let count = backtrace(&frames, 128)
                backtrace_symbols_fd(&frames, count, fd)
                close(fd)
            }
        }
        // Restore whichever handler was there before us (or the default) and re-raise.
        if var old = previousActions[sig] {
            sigaction(sig, &old, nil)
        } else {
            signal(sig, SIG_DFL)
        }
        raise(sig)
    }
}
#endif
