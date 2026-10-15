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
        currentTest = BuildBarberTest(
            title: "Test session",
            instructions: "Tick each item as you complete it, then submit your result.",
            checklist: configuration.checklistItems.map {
                BuildBarberTest.ChecklistItem(key: $0, label: $0, kind: "task")
            },
            showPassFailButtons: true)
        presentConfirmation(from: viewController)
    }

    private func presentConfirmation(from viewController: UIViewController) {
        let alert = UIAlertController(
            title: "Record this session?",
            message: "This session will record your screen and audio while you test. Recording only starts after you confirm and select what to share. Submit your result from the session menu when finished.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { [weak self] _ in
            Task { @MainActor in await self?.beginRecording(from: viewController) }
        })
        viewController.present(alert, animated: true)
    }

    private func beginRecording(from viewController: UIViewController) async {
        do {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            try await recorder.start()
        } catch {
            return // user cancelled the picker or permission was denied
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
    }

    // MARK: Menu

    private func presentMenu() {
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

    private func dismissMenu() {
        menuController?.dismiss(animated: true)
        menuController = nil
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
        guard isActive, !awaitingFeedback else { return }
        awaitingFeedback = true
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "BuildBarber.finalize")
        pendingVideoURL = await recorder.stop()
        if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }

        let content = UNMutableNotificationContent()
        content.title = "Session paused"
        content.body = "Your session was paused. Tap here to provide feedback and submit your result."
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
        try await configuration.client.submitTestResult(result, videoURL: pendingVideoURL)
        if let videoURL = pendingVideoURL { await saveToCameraRoll(videoURL) }
        dismissMenu()
        await finishSession()
    }

    private func saveToCameraRoll(_ url: URL) async {
        let authorizationStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
        guard authorizationStatus == .authorized else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHPhotoLibrary.shared().performChanges({
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { _, _ in
                continuation.resume()
            }
        }
    }

    private func finishSession() async {
        guard isActive else { return }
        isActive = false
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
