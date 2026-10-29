#if canImport(UIKit) && canImport(ReplayKit)
import AVFoundation
import ReplayKit
import UIKit

enum RecorderError: Error, LocalizedError, Sendable {
    case unavailable
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Screen recording is not available on this device."
        case .writerFailed(let message): return message
        }
    }
}

/// Writes captured sample buffers to a file. All mutation happens on `queue`.
final class SampleWriter: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.buildbarber.sdk.writer")
    let url: URL
    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?
    private var started = false
    private var finished = false

    init(url: URL) { self.url = url }

    /// Must be called on `queue`.
    func append(_ buffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard !finished, buffer.isValid, CMSampleBufferDataIsReady(buffer) else { return }
        do {
            if writer == nil { try setUp(for: buffer, type: type) }
            guard let writer, writer.status == .writing || writer.status == .unknown else { return }
            if !started {
                guard type == .video else { return }
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
                started = true
            }
            let input = (type == .video) ? video : (type == .audioApp ? audio : nil)
            if let input, input.isReadyForMoreMediaData { input.append(buffer) }
        } catch {
            finished = true
        }
    }

    private func setUp(for buffer: CMSampleBuffer, type: RPSampleBufferType) throws {
        guard type == .video, let format = CMSampleBufferGetFormatDescription(buffer) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // Fragments keep the file playable if the app crashes before the writer is finalized.
        w.movieFragmentInterval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dims.width),
            AVVideoHeightKey: Int(dims.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: RecordingLimits.videoBitRate,
                // Frequent keyframes let each 0.1s fragment be decoded independently after a crash.
                AVVideoMaxKeyFrameIntervalDurationKey: 0.1,
                AVVideoAllowFrameReorderingKey: false
            ]
        ])
        v.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: RecordingLimits.audioBitRate
        ])
        a.expectsMediaDataInRealTime = true
        guard w.canAdd(v) else {
            throw RecorderError.writerFailed("The video encoder is not supported on this device.")
        }
        w.add(v)
        if w.canAdd(a) {
            w.add(a)
            audio = a
        }
        writer = w
        video = v
    }

    /// Finishes the file. Returns nil if nothing was recorded.
    func finish() async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            queue.async {
                self.finished = true
                guard let writer = self.writer, self.started, writer.status == .writing else {
                    self.writer?.cancelWriting()
                    cont.resume(returning: nil)
                    return
                }
                self.video?.markAsFinished()
                self.audio?.markAsFinished()
                let url = self.url
                writer.finishWriting {
                    cont.resume(returning: writer.status == .completed ? url : nil)
                }
            }
        }
    }
}

/// Keeps recorder access on the main actor while creating ReplayKit callbacks off-actor.
@MainActor
enum ReplayKitBridge {
    static func startCapture(
        recorder: RPScreenRecorder,
        writer: SampleWriter,
        queue: DispatchQueue,
        onError: @escaping @Sendable (Error) -> Void,
        onStartFailed: @escaping @Sendable @MainActor () -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture(
                handler: sampleHandler(writer: writer, queue: queue, onError: onError),
                completionHandler: startCompletionHandler(
                    continuation: continuation,
                    onStartFailed: onStartFailed))
        }
    }

    static func stopCapture(recorder: RPScreenRecorder) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            recorder.stopCapture(handler: stopCompletionHandler(continuation: continuation))
        }
    }

    private nonisolated static func sampleHandler(
        writer: SampleWriter,
        queue: DispatchQueue,
        onError: @escaping @Sendable (Error) -> Void
    ) -> @Sendable (CMSampleBuffer, RPSampleBufferType, Error?) -> Void {
        { sampleBuffer, type, error in
            if let error {
                onError(error)
                return
            }
            queue.async {
                writer.append(sampleBuffer, type: type)
            }
        }
    }

    private nonisolated static func startCompletionHandler(
        continuation: CheckedContinuation<Void, Error>,
        onStartFailed: @escaping @Sendable @MainActor () -> Void
    ) -> @Sendable (Error?) -> Void {
        { error in
            if let error {
                Task { @MainActor in
                    onStartFailed()
                    continuation.resume(throwing: error)
                }
            } else {
                continuation.resume()
            }
        }
    }

    private nonisolated static func stopCompletionHandler(
        continuation: CheckedContinuation<Void, Never>
    ) -> @Sendable (Error?) -> Void {
        { _ in continuation.resume() }
    }
}

/// Captures the app's screen and audio with ReplayKit.
@MainActor
final class ScreenRecorder {
    private let screenRecorder = RPScreenRecorder.shared()
    private var writer: SampleWriter?
    /// Called on the main actor if capture stops unexpectedly.
    var onStreamError: (@MainActor (Error) -> Void)?

    var isRecording: Bool { writer != nil }

    /// The file currently being written, if recording.
    var currentVideoFileName: String? { writer?.url.lastPathComponent }

    /// Starts capturing the app's screen and audio.
    func start() async throws {
        guard writer == nil else { return }
        guard screenRecorder.isAvailable else { throw RecorderError.unavailable }

        let url = CrashReporter.videoURL(fileName: "session-\(UUID().uuidString).mp4")
        let writer = SampleWriter(url: url)
        self.writer = writer
        screenRecorder.isMicrophoneEnabled = false
        let queue = writer.queue
        let recorder = screenRecorder
        let onError: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor in self?.handleStop(error, from: writer) }
        }
        // Only clear the writer if a newer start/stop cycle hasn't replaced it.
        let onStartFailed: @Sendable @MainActor () -> Void = { [weak self] in
            if self?.writer === writer { self?.writer = nil }
        }
        try await ReplayKitBridge.startCapture(
            recorder: recorder, writer: writer, queue: queue, onError: onError, onStartFailed: onStartFailed)
    }

    /// Stops capture and returns the finalized video URL, if any frames were written.
    func stop() async -> URL? {
        guard let writer else { return nil }
        self.writer = nil
        await ReplayKitBridge.stopCapture(recorder: screenRecorder)
        return await writer.finish()
    }

    private func handleStop(_ error: Error, from source: SampleWriter) {
        guard writer === source else { return }
        onStreamError?(error)
    }
}
#endif
