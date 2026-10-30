#if canImport(UIKit) && canImport(ZipArchive)
import Foundation
import UIKit
import ZipArchive

enum CrashArchiveBundler {
    private static let maximumSearchDepth = 3

    static func makeArchive(crashLogURL: URL, appGroupIdentifier: String?) throws -> URL? {
        let dsymURLs = findDsyms(appGroupIdentifier: appGroupIdentifier)
        guard !dsymURLs.isEmpty else { return nil }

        let fileManager = FileManager.default
        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BuildBarberCrash-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = fileManager.temporaryDirectory
            .appendingPathComponent("BuildBarberCrash-\(UUID().uuidString).zip")
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        try fileManager.copyItem(at: crashLogURL, to: stagingDirectory.appendingPathComponent("crash.log"))
        var usedNames = Set<String>()
        for dsymURL in dsymURLs {
            let destinationName = uniqueBundleName(dsymURL.lastPathComponent, usedNames: &usedNames)
            try fileManager.copyItem(
                at: dsymURL,
                to: stagingDirectory.appendingPathComponent(destinationName, isDirectory: true))
        }

        guard SSZipArchive.createZipFile(
            atPath: archiveURL.path,
            withContentsOfDirectory: stagingDirectory.path,
            keepParentDirectory: false)
        else {
            try? fileManager.removeItem(at: archiveURL)
            throw CrashArchiveError.zipCreationFailed
        }
        return archiveURL
    }

    private static func findDsyms(appGroupIdentifier: String?) -> [URL] {
        let fileManager = FileManager.default
        var roots = [
            Bundle.main.bundleURL,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        if let appGroupIdentifier,
           let groupURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            roots.append(groupURL)
        }

        var visited = Set<String>()
        var dsymPaths = Set<String>()
        var dsymURLs: [URL] = []
        for root in roots {
            guard visited.insert(root.standardizedFileURL.path).inserted else { continue }
            for candidate in dsymBundles(under: root) {
                let path = candidate.standardizedFileURL.path
                if dsymPaths.insert(path).inserted, hasDwarfFiles(candidate) {
                    dsymURLs.append(candidate)
                }
            }
        }
        return dsymURLs
    }

    private static func uniqueBundleName(_ name: String, usedNames: inout Set<String>) -> String {
        guard !usedNames.insert(name).inserted else {
            let base = String(name.dropLast(".dSYM".count))
            var suffix = 2
            while !usedNames.insert("\(base)-\(suffix).dSYM").inserted { suffix += 1 }
            return "\(base)-\(suffix).dSYM"
        }
        return name
    }

    private static func dsymBundles(under root: URL) -> [URL] {
        let fileManager = FileManager.default
        var results: [URL] = []
        var pending: [(url: URL, depth: Int)] = [(root, 0)]

        while let current = pending.popLast() {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
            else {
                continue
            }

            for entry in entries {
                if entry.pathExtension.caseInsensitiveCompare("dSYM") == .orderedSame {
                    results.append(entry)
                } else if current.depth < maximumSearchDepth - 1,
                          (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    pending.append((entry, current.depth + 1))
                }
            }
        }
        return results
    }

    private static func hasDwarfFiles(_ dsymURL: URL) -> Bool {
        let dwarfDirectory = dsymURL
            .appendingPathComponent("Contents/Resources/DWARF", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dwarfDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else {
            return false
        }
        return files.contains {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private enum CrashArchiveError: Error {
        case zipCreationFailed
    }
}
#endif
