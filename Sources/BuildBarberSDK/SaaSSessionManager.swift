#if canImport(UIKit) && canImport(ScreenCaptureKit)
import SwiftUI
import UIKit
import UserNotifications

/// Entry point of the SDK.
@MainActor
public final class SaaSSessionManager {
    public static let shared = SaaSSessionManager()

    private struct Configuration {
        let apiKey: String
        let endpoint: URL
    }

    private var configuration: Configuration?
    private let model = SessionModel()
    private let recorder = ScreenRecorder()
    private var overlay: FloatingOverlay?
    private var menuController: UIViewController?
    private var startedAt = Date()
    private var sessionID = UUID().uuidString
    private var interrupted = false
    private var pendingVideoURL: URL?
    private var awaitingFeedback = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var isActive = false

    public init() {}

    // MARK: Configuration

    public func configure(apiKey: String, apiEndpoint: URL, checklistItems: [String]) {
        configuration = Configuration(apiKey: apiKey, endpoint: apiEndpoint)
        model.items = checklistItems.enumerated().map { ChecklistEntry(id: $0.offset, title: $0.element, isTicked: false) }
        model.feedback = ""
    }

    /// Ticks or unticks a checklist item. Out-of-range indices are ignored.
    public func updateChecklist(itemIndex: Int, isTicked: Bool) {
        guard model.items.indices.contains(itemIndex) else { return }
        model.items[itemIndex].isTicked = isTicked
    }

    // MARK: Session start

    public func startSession(presentingFrom viewController: UIViewController) {
        guard configuration != nil, !isActive else { return }
        let alert = UIAlertController(
            title: "Record this session?",
            message: "This session will record your screen and audio so you can share feedback. Recording only starts after you confirm and select what to share. You can end it at any time from the floating button.",
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
        interrupted = false
        awaitingFeedback = false
        pendingVideoURL = nil
        sessionID = UUID().uuidString
        startedAt = Date()
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
        let view = ChecklistMenuView(
            model: model,
            onContinue: { [weak self] in self?.dismissMenu() },
            onEnd: { [weak self] in
                self?.dismissMenu()
                Task { @MainActor in await self?.endSession() }
            })
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
        interrupted = true
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "BuildBarber.finalize")
        pendingVideoURL = await recorder.stop()
        if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }

        let content = UNMutableNotificationContent()
        content.title = "Session paused"
        content.body = "Your session was paused. Tap here to provide feedback and upload your session."
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

    private func endSession() async {
        guard isActive, let configuration else { return }
        isActive = false
        stopObserving()
        overlay?.hide()
        overlay = nil
        let videoURL: URL? = if awaitingFeedback { pendingVideoURL } else { await recorder.stop() }
        pendingVideoURL = nil
        awaitingFeedback = false

        let device = UIDevice.current
        let info = Bundle.main.infoDictionary
        let payload = SessionPayload(
            checklist: model.items,
            feedback: model.feedback,
            metadata: .init(
                sessionID: sessionID,
                startedAt: startedAt,
                endedAt: Date(),
                wasInterruptedByBackground: interrupted,
                appBundleID: Bundle.main.bundleIdentifier ?? "",
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "",
                osVersion: device.systemVersion,
                deviceModel: device.model))
        let uploader = SessionUploader(apiKey: configuration.apiKey, endpoint: configuration.endpoint)

        let taskID = UIApplication.shared.beginBackgroundTask(withName: "BuildBarber.upload")
        do {
            try await uploader.upload(payload: payload, videoURL: videoURL)
            if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        } catch {
            // Keep the file on failure so the host can retry later.
        }
        if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
    }
}
#endif
