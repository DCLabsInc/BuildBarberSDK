#if canImport(UIKit) && canImport(ScreenCaptureKit)
import AuthenticationServices
import SwiftUI
import UIKit

private struct RewardBanner: View {
    let reward: SdkRewardInfo
    let signedIn: Bool

    private var accent: Color { signedIn ? .green : .yellow }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.title)
                        .font(.headline)
                    if let description = reward.description, !description.isEmpty {
                        Text(description)
                    }
                }
            }
            Text(signedIn ? "Signed in. Reward pending." : "Sign in below for reward")
                .font(.subheadline.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.75)))
        .accessibilityElement(children: .combine)
    }
}

private struct BuildBarberBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("tache", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("BuildBarber")
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
                    Text("Record your session to earn the \(reward.title) reward. Then sign in with Apple when you submit your test result to get your reward instructions.")
                } else {
                    Text("Test session recording")
                        .font(.title2.weight(.semibold))
                    Text("Recording helps us fix more bugs. On the next screen, tap “Share entire screen,” then tap anywhere below to start testing.")
                }

                BuildBarberBrand()
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack {
                    Button("Don't record") { choose(record: false) }
                        .buttonStyle(.bordered)
                        .tint(.yellow)
                    Spacer()
                    Button("Record session") { choose(record: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.yellow.opacity(0.7)))
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
                                .foregroundStyle(.yellow)
                            Text(item.label)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { feedbackIsFocused = false })

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                           let email = credential.email ?? Self.email(fromIdentityToken: credential.identityToken) {
                            testerEmail = email
                            isSignedIn = true
                            UserDefaults.standard.set(email, forKey: Self.appleEmailDefaultsKey)
                            signInError = nil
                        } else {
                            isSignedIn = true
                            signInError = nil
                        }
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
                .simultaneousGesture(TapGesture().onEnded { feedbackIsFocused = false })

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
                    .tint(.yellow)
                    .disabled(isSubmitting)

                    Button("Fail") {
                        submit(outcome: "fail")
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)
                    .disabled(isSubmitting)
                } else {
                    Button("Submit feedback") {
                        submit(outcome: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
                Spacer()
                BuildBarberBrand()
            }
            .simultaneousGesture(TapGesture().onEnded { feedbackIsFocused = false })
            .padding(.horizontal)
            .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .navigationTitle(test.title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(.yellow)
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
        .preferredColorScheme(.dark)
    }

    /// Apple only populates `credential.email` on the first authorization; the identity token's
    /// `email` claim is present on every sign-in.
    private static func email(fromIdentityToken token: Data?) -> String? {
        guard let token, let jwt = String(data: token, encoding: .utf8) else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = claims["email"] as? String, !email.isEmpty else { return nil }
        return email
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
