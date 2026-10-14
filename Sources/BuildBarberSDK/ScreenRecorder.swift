#if canImport(UIKit) && canImport(ScreenCaptureKit)
import AVFoundation
import ScreenCaptureKit
import UIKit

enum RecorderError: Error, Sendable {
    case cancelled
    case writerFailed(String)
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
    func append(_ buffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard !finished, buffer.isValid, CMSampleBufferDataIsReady(buffer) else { return }
        do {
            if writer == nil { try setUp(for: buffer, type: type) }
            guard let writer, writer.status == .writing || writer.status == .unknown else { return }
            if !started {
                guard type == .screen else { return }
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
                started = true
            }
            let input = (type == .screen) ? video : audio
            if let input, input.isReadyForMoreMediaData { input.append(buffer) }
        } catch {
            finished = true
        }
    }

    private func setUp(for buffer: CMSampleBuffer, type: SCStreamOutputType) throws {
        guard type == .screen, let format = CMSampleBufferGetFormatDescription(buffer) else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dims.width),
            AVVideoHeightKey: Int(dims.height)
        ])
        v.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        a.expectsMediaDataInRealTime = true
        if w.canAdd(v) { w.add(v) }
        if w.canAdd(a) { w.add(a) }
        writer = w; video = v; audio = a
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

/// Wraps SCStream and the content sharing picker.
@MainActor
final class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var writer: SampleWriter?
    private var pickerContinuation: CheckedContinuation<SCContentFilter, Error>?
    private let output = StreamOutput()
    /// Called on the main actor if the stream stops unexpectedly.
    var onStreamError: (@MainActor (Error) -> Void)?

    var isRecording: Bool { stream != nil }

    /// Asks the user (via the system picker) which content to share, then starts capturing.
    func start() async throws {
        guard stream == nil else { return }
        let filter = try await pickContent()
        let config = SCStreamConfiguration()
        config.capturesAudio = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-\(UUID().uuidString).mp4")
        let writer = SampleWriter(url: url)
        output.writer = writer
        output.onStop = { [weak self] error in
            Task { @MainActor in self?.handleStop(error) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: writer.queue)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: writer.queue)
        try await stream.startCapture()
        self.stream = stream
        self.writer = writer
    }

    /// Stops capture and returns the finalized video URL, if any frames were written.
    func stop() async -> URL? {
        let stream = self.stream, writer = self.writer
        self.stream = nil
        self.writer = nil
        try? await stream?.stopCapture()
        return await writer?.finish()
    }

    private func handleStop(_ error: Error) {
        guard stream != nil else { return }
        onStreamError?(error)
    }

    private func pickContent() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        picker.isActive = true
        defer { picker.remove(self); picker.isActive = false }
        return try await withCheckedThrowingContinuation { cont in
            pickerContinuation = cont
            picker.present()
        }
    }

    private func resolvePicker(_ result: Result<SCContentFilter, Error>) {
        pickerContinuation?.resume(with: result)
        pickerContinuation = nil
    }
}

extension ScreenRecorder: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        nonisolated(unsafe) let filter = filter
        Task { @MainActor in self.resolvePicker(.success(filter)) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.resolvePicker(.failure(RecorderError.cancelled)) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in self.resolvePicker(.failure(error)) }
    }
}

private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var writer: SampleWriter?
    var onStop: (@Sendable (Error) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Invoked on writer.queue.
        writer?.append(sampleBuffer, type: type)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop?(error)
    }
}
#endif
