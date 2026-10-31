import Foundation

/// Size and duration limits for session recordings, based on the portal's upload limit.
enum RecordingLimits {
    static let maxUploadBytes: Int64 = 100_000_000
    static let videoBitRate = 1_000_000
    static let audioBitRate = 128_000
    static let keyFrameInterval = 1.0
    static let maxLongSide = 1280

    /// Downscales so the longest side fits `maxLongSide`, keeping aspect ratio and even dimensions.
    static func scaledSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longSide = max(width, height)
        guard longSide > maxLongSide else { return (width, height) }
        let scale = Double(maxLongSide) / Double(longSide)
        func even(_ v: Int) -> Int { max(2, Int((Double(v) * scale / 2).rounded()) * 2) }
        return (even(width), even(height))
    }

    /// Encoders only target the average bitrate, so stop early to leave headroom.
    static let safetyFactor = 0.85

    static var maxDuration: TimeInterval {
        Double(maxUploadBytes) * 8 / Double(videoBitRate + audioBitRate) * safetyFactor
    }

    static func exceedsUploadLimit(fileSize: Int64) -> Bool {
        fileSize > maxUploadBytes
    }

    static func fileSize(at url: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }
}
