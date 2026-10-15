#if canImport(UIKit) && canImport(ScreenCaptureKit)
import Combine
import Photos
import SwiftUI
import UIKit
import UserNotifications

/// Entry point of the SDK.
@MainActor
public final class BuildBarberSessionManager: ObservableObject {
    public static let shared = BuildBarberSessionManager()

    private struct Configuration {
        let client: BuildBarberClient
        let testType: BuildBarberTestType
        let codeword: String
        let checklistItems: [String]
    }

    private var configuration: Configuration?
    private var currentTest: BuildBarberTest?
    @Published private var checkedItems = Set<String>()
    private let recorder = ScreenRecorder()
    private var overlay: FloatingOverlay?
    private var menuController: UIViewController?
    private var pendingVideoURL: URL?
    private var awaitingFeedback = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var isActive = false
    private var limitTask: Task<Void, Never>?
    public init() {}

    // MARK: Configuration

    public func configure(
        apiKey: String,
        testType: BuildBarberTestType,
        codeword: String,
        checklistItems: [String]
    ) {
        configuration = Configuration(
            client: BuildBarberClient(configuration: BuildBarberConfiguration(apiKey: apiKey)),
            testType: testType,
            codeword: codeword,
            checklistItems: checklistItems)
    }

    /// Automatically ticks a configured checklist item during an active session.
    /// The index is zero-based and refers to the order of `checklistItems` passed to `configure`.
    public func tickChecklistItem(at index: Int) {
        guard isActive,
              let configuration,
              configuration.checklistItems.indices.contains(index)
        else { return }
        checkedItems.insert(configuration.checklistItems[index])
    }

    var checkedChecklistItemKeys: Set<String> { checkedItems }

    func toggleChecklistItem(key: String) {
        if checkedItems.contains(key) {
            checkedItems.remove(key)
        } else {
            checkedItems.insert(key)
        }
    }

    // MARK: Session start

    public func startSession(presentingFrom viewController: UIViewController) {
        guard let configuration, !isActive else { return }
        checkedItems.removeAll()
        Task { @MainActor in
            // If the definition can't be fetched, fall back to the feedback-only flow.
            let showPassFail = (try? await configuration.client.fetchShowPassFailButtons(
                testType: configuration.testType, codeword: configuration.codeword)) ?? false
            guard !self.isActive else { return }
            self.currentTest = BuildBarberTest(
                title: "Test session",
                instructions: "Tick each item as you complete it, then submit your result.",
                checklist: configuration.checklistItems.map {
                    BuildBarberTest.ChecklistItem(key: $0, label: $0, kind: "task")
                },
                showPassFailButtons: showPassFail)
            self.presentConfirmation(from: viewController)
        }
    }

    private func presentConfirmation(from viewController: UIViewController) {
        let alert = UIAlertController(
            title: "Test session recording",
            message: "Recording helps us fix more bugs. On next screen tap 'Share entire screen' then tap anywhere below to start testing.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Don't record", style: .cancel) { [weak self] _ in
            Task { @MainActor in await self?.beginRecording(from: viewController, record: false) }
        })
        alert.addAction(UIAlertAction(title: "Record session", style: .default) { [weak self] _ in
            Task { @MainActor in await self?.beginRecording(from: viewController, record: true) }
        })
        viewController.present(alert, animated: true)
    }

    private func beginRecording(from viewController: UIViewController, record: Bool) async {
        var recording = record
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        if record {
            do {
                try await recorder.start()
            } catch {
                // The session continues without video so testers can still submit feedback.
                recording = false
                if case RecorderError.cancelled = error {} else {
                    let alert = UIAlertController(
                        title: "Couldn't start recording",
                        message: "\(error.localizedDescription)\n\n(\(String(reflecting: error)))\n\nYou can still submit your feedback without a video.",
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    Self.topMost(from: viewController).present(alert, animated: true)
                }
            }
        }
        isActive = true
        awaitingFeedback = false
        pendingVideoURL = nil
        recorder.onStreamError = { [weak self] _ in
            Task { @MainActor in await self?.handleInterruption() }
        }
        if let scene = viewController.view.window?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let overlay = FloatingOverlay { [weak self] in self?.presentMenu() }
            overlay.show(in: scene)
            self.overlay = overlay
        }
        observeLifecycle()
        if recording { scheduleRecordingLimit() }
    }

    private func scheduleRecordingLimit() {
        limitTask?.cancel()
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RecordingLimits.maxDuration))
            guard !Task.isCancelled else { return }
            await self?.handleRecordingLimitReached()
        }
    }

    private func handleRecordingLimitReached() async {
        guard isActive, !awaitingFeedback else { return }
        awaitingFeedback = true
        pendingVideoURL = await recorder.stop()

        let minutes = Int((RecordingLimits.maxDuration / 60).rounded(.down))
        let alert = UIAlertController(
            title: "Recording stopped",
            message: "Recording stopped automatically after about \(minutes) minutes to keep the video under 100 MB. Please submit your feedback now.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            Task { @MainActor in self?.presentMenu() }
        })
        if let presenter = overlay?.presenter {
            Self.topMost(from: presenter).present(alert, animated: true)
        }
    }

    private static func topMost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    private func presentOversizeAlert(in scene: UIWindowScene?, savedToPhotos: Bool, bytes: Int64) {
        guard let window = scene?.windows.first(where: { !($0 is PassthroughWindow) && $0.isKeyWindow })
            ?? scene?.windows.first(where: { !($0 is PassthroughWindow) }),
              let root = window.rootViewController
        else { return }
        let megabytes = Int((Double(bytes) / 1_000_000).rounded())
        let location = savedToPhotos
            ? "It has been saved to your Photos library. Please upload it manually from there."
            : "It could not be saved to your Photos library."
        let alert = UIAlertController(
            title: "Video too large to upload",
            message: "Your recording is \(megabytes) MB, which is over the 100 MB upload limit, so it was not uploaded. Your feedback was submitted. \(location)",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        Self.topMost(from: root).present(alert, animated: true)
    }

    // MARK: Menu

    private func presentMenu() {
        // A swipe-dismissed sheet leaves a stale reference behind.
        if let menu = menuController, menu.presentingViewController == nil { menuController = nil }
        guard menuController == nil, let presenter = overlay?.presenter else { return }
        guard let test = currentTest else { return }
        let view = ChecklistMenuView(test: test, sessionManager: self) { [weak self] outcome, email, feedback, checkedItems in
            guard let self, let configuration = self.configuration else { return }
            let result = BuildBarberTestResult(
                testType: configuration.testType,
                codeword: configuration.codeword,
                testerEmail: email,
                outcome: outcome,
                feedback: feedback,
                checkedItems: checkedItems)
            try await self.submit(result)
        }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        menuController = host
        presenter.present(host, animated: true)
    }

    private func dismissMenu() async {
        guard let menu = menuController else { return }
        menuController = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            menu.dismiss(animated: true) { continuation.resume() }
        }
    }

    // MARK: Lifecycle

    private func observeLifecycle() {
        let center = NotificationCenter.default
        backgroundObserver = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleInterruption() }
        }
        foregroundObserver = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleForeground() }
        }
    }

    private func stopObserving() {
        [backgroundObserver, foregroundObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        backgroundObserver = nil
        foregroundObserver = nil
    }

    private func handleInterruption() async {
        guard isActive else { return }
        if !awaitingFeedback {
            awaitingFeedback = true
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "BuildBarber.finalize")
            pendingVideoURL = await recorder.stop()
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }

        let content = UNMutableNotificationContent()
        content.title = "Feedback needed"
        content.body = "Tap here to return to the app and submit your test feedback."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "com.buildbarber.sdk.paused", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func handleForeground() {
        guard isActive, awaitingFeedback else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["com.buildbarber.sdk.paused"])
        presentMenu()
    }

    // MARK: Completion

    private func submit(_ result: BuildBarberTestResult) async throws {
        guard isActive, let configuration else { return }
        if !awaitingFeedback && pendingVideoURL == nil {
            pendingVideoURL = await recorder.stop()
        }
        let videoSize = pendingVideoURL.map(RecordingLimits.fileSize(at:)) ?? 0
        let tooLarge = RecordingLimits.exceedsUploadLimit(fileSize: videoSize)
        try await configuration.client.submitTestResult(result, videoURL: tooLarge ? nil : pendingVideoURL)
        var savedToPhotos = false
        if let videoURL = pendingVideoURL { savedToPhotos = await saveToCameraRoll(videoURL) }
        let scene = overlay?.presenter?.view.window?.windowScene
        await dismissMenu()
        await finishSession()
        if tooLarge { presentOversizeAlert(in: scene, savedToPhotos: savedToPhotos, bytes: videoSize) }
    }

    @discardableResult
    private func saveToCameraRoll(_ url: URL) async -> Bool {
        await Self.saveVideoToPhotoLibrary(url)
    }

    // Nonisolated so Photos' callbacks, which run on its own queues, are not main-actor isolated.
    private nonisolated static func saveVideoToPhotoLibrary(_ url: URL) async -> Bool {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
    }

    private func finishSession() async {
        guard isActive else { return }
        isActive = false
        limitTask?.cancel()
        limitTask = nil
        stopObserving()
        overlay?.hide()
        overlay = nil
        var videoURL = pendingVideoURL
        if videoURL == nil && !awaitingFeedback {
            videoURL = await recorder.stop()
        }
        pendingVideoURL = nil
        awaitingFeedback = false
        checkedItems.removeAll()
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        currentTest = nil
    }
}
#endif
