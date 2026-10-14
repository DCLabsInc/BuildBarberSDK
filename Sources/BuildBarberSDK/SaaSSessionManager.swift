#if canImport(UIKit) && canImport(ScreenCaptureKit)
import SwiftUI
import UIKit
import UserNotifications

/// Entry point of the SDK.
@MainActor
public final class SaaSSessionManager {
    public static let shared = SaaSSessionManager()

    private struct Configuration {
        let client: BuildBarberClient
        let testType: BuildBarberTestType
        let codeword: String
    }

    private var configuration: Configuration?
    private var currentTest: BuildBarberTest?
    private let recorder = ScreenRecorder()
    private var overlay: FloatingOverlay?
    private var menuController: UIViewController?
    private var pendingVideoURL: URL?
    private var awaitingFeedback = false
    private var isLoadingTest = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var isActive = false

    public init() {}

    // MARK: Configuration

    public func configure(apiKey: String, testType: BuildBarberTestType, codeword: String) {
        configuration = Configuration(
            client: BuildBarberClient(configuration: BuildBarberConfiguration(apiKey: apiKey)),
            testType: testType,
            codeword: codeword)
    }

    // MARK: Session start

    public func startSession(presentingFrom viewController: UIViewController) {
        guard let configuration, !isActive, !isLoadingTest else { return }
        isLoadingTest = true
        Task {
            defer { isLoadingTest = false }
            do {
                currentTest = try await configuration.client.fetchTest(
                    type: configuration.testType,
                    codeword: configuration.codeword)
                presentConfirmation(from: viewController)
            } catch {
                let message: String
                if let apiError = error as? BuildBarberError,
                   case let .api(_, body) = apiError,
                   body.error == "test_not_found" {
                    message = "The test could not be found. Check the codeword and try again."
                } else {
                    message = "The test could not be loaded. Please try again."
                }
                showError(message, from: viewController)
            }
        }
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

    private func showError(_ message: String, from viewController: UIViewController) {
        let alert = UIAlertController(title: "Unable to load test", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
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
        let view = ChecklistMenuView(test: test) { [weak self] outcome, email, feedback, checkedItems in
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
        try await configuration.client.submitTestResult(result)
        dismissMenu()
        await finishSession()
    }

    private func finishSession() async {
        guard isActive else { return }
        isActive = false
        stopObserving()
        overlay?.hide()
        overlay = nil
        let videoURL: URL? = if awaitingFeedback { pendingVideoURL } else { await recorder.stop() }
        pendingVideoURL = nil
        awaitingFeedback = false
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        currentTest = nil
    }
}
#endif
