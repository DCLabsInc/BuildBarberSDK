#if canImport(UIKit) && canImport(ReplayKit)
import AuthenticationServices
import SwiftUI
import UIKit

private struct RewardBanner: View {
    let reward: SdkRewardInfo
    let signedIn: Bool

    private var accent: Color { signedIn ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reward: \(reward.description)")
                        .font(.headline)
                    if let group = reward.groupTitle, !group.isEmpty, group != reward.description {
                        Text(group)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(signedIn ? "Signed in. Reward pending." : "Sign in for reward")
                .font(.subheadline.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.75)))
        .accessibilityElement(children: .combine)
    }
}

private struct TestBarberBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("🍊 TestJuice")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

struct SessionConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let reward: SdkRewardInfo?
    let onChoose: (Bool) -> Void

    private func choose(record: Bool) {
        Task { @MainActor in
            dismiss()
            try? await Task.sleep(for: .milliseconds(300))
            onChoose(record)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                if let reward {
                    RewardBanner(reward: reward, signedIn: false)
                    Text("Record your session to earn the reward: \(reward.description). Then sign in with Apple when you submit your test result to get your reward instructions.")
                } else {
                    Text("Test session recording")
                        .font(.title2.weight(.semibold))
                    Text("Recording helps us fix more bugs. Once recording starts, return to your app and test as usual.")
                }

                TestBarberBrand()
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack {
                    Button("Don't record") { choose(record: false) }
                        .buttonStyle(.bordered)
                        .tint(.black)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Record session") { choose(record: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .foregroundStyle(.black)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.7)))
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
}

struct ChecklistMenuView: View {
    private static let appleEmailDefaultsKey = "com.buildbarber.sdk.testerEmail"

    let test: BuildBarberTest
    @ObservedObject var sessionManager: BuildBarberSessionManager
    var initialFeedback = ""
    let onSubmit: (String?, String, String, [String]) async throws -> Void

    @State private var testerEmail = UserDefaults.standard.string(forKey: Self.appleEmailDefaultsKey) ?? ""
    @State private var isSignedIn = !(UserDefaults.standard.string(forKey: Self.appleEmailDefaultsKey) ?? "").isEmpty
    @State private var signInError: String?
    @State private var feedback: String
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var errorDetails: String?
    @State private var showingErrorDetails = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var feedbackIsFocused: Bool

    init(
        test: BuildBarberTest,
        sessionManager: BuildBarberSessionManager,
        initialFeedback: String = "",
        onSubmit: @escaping (String?, String, String, [String]) async throws -> Void
    ) {
        self.test = test
        self.sessionManager = sessionManager
        self.initialFeedback = initialFeedback
        self.onSubmit = onSubmit
        _feedback = State(initialValue: initialFeedback)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let reward = test.reward {
                    RewardBanner(reward: reward, signedIn: isSignedIn)
                    .padding(.horizontal)
                    .onTapGesture { feedbackIsFocused = false }
                }

                List(test.checklist, id: \.key) { item in
                    Button {
                        sessionManager.toggleChecklistItem(key: item.key)
                    } label: {
                        HStack {
                            Image(systemName: sessionManager.checkedChecklistItemKeys.contains(item.key) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(.orange)
                            Text(item.label)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { feedbackIsFocused = false })

                if isSignedIn {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                        Text("Signed in as \(testerEmail)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        feedbackIsFocused = false
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let email = AppleSignInEmail.resolve(
                                    credentialEmail: credential.email,
                                    identityToken: credential.identityToken
                                  )
                            else {
                                isSignedIn = false
                                signInError = "Apple sign-in succeeded, but no email was provided. Please try again."
                                return
                            }
                            testerEmail = email
                            isSignedIn = true
                            UserDefaults.standard.set(email, forKey: Self.appleEmailDefaultsKey)
                            signInError = nil
                        case .failure(let error):
                            if let authorizationError = error as? ASAuthorizationError,
                               authorizationError.code == .unknown {
                                signInError = "Sign in with Apple failed. Check that the host app has the Sign in with Apple capability enabled."
                            } else {
                                signInError = error.localizedDescription
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .padding(.horizontal)
                }

                if let signInError {
                    Text(signInError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                TextEditor(text: $feedback)
                    .focused($feedbackIsFocused)
                    .frame(minHeight: 60, maxHeight: 60)
                    .overlay(alignment: .topLeading) {
                        if feedback.isEmpty {
                            Text("What did you like, dislike or think should be added?")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                    .padding(.horizontal)
                    .padding(.bottom, 5)

                if let submissionError {
                    Text(submissionError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                if test.showPassFailButtons {
                    Button("Pass") {
                        submit(outcome: "pass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .foregroundStyle(.black)
                    .disabled(isSubmitting)

                    Button("Fail") {
                        submit(outcome: "fail")
                    }
                    .buttonStyle(.bordered)
                    .tint(.black)
                    .foregroundStyle(.white)
                    .disabled(isSubmitting)
                } else {
                    Button("Submit feedback") {
                        submit(outcome: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .foregroundStyle(.black)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
                Spacer()
                TestBarberBrand()
            }
            .simultaneousGesture(TapGesture().onEnded { feedbackIsFocused = false })
            .padding(.horizontal)
            .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .navigationTitle(test.title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(.orange)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("X") { dismiss() }
                }
            }
            .alert("Error submitting feedback", isPresented: $showingErrorDetails) {
                Button("Copy to clipboard") {
                    UIPasteboard.general.string = errorDetails
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorDetails ?? "")
            }
        }
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Submitting test results")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .preferredColorScheme(.dark)
    }

    private func submit(outcome: String?) {
        isSubmitting = true
        submissionError = nil
        Task {
            do {
                // The server requires feedback text when failing a test.
                let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = trimmed.isEmpty && outcome == "fail" ? "No feedback provided" : feedback
                try await onSubmit(
                    outcome,
                    testerEmail,
                    text,
                    test.checklist.filter { sessionManager.checkedChecklistItemKeys.contains($0.key) }.map(\.key))
            } catch {
                submissionError = error.localizedDescription
                errorDetails = (error as? BuildBarberError)?.detailedDescription ?? String(describing: error)
                showingErrorDetails = true
                isSubmitting = false
            }
        }
    }
}
#endif
