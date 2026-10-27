#if canImport(UIKit) && canImport(ScreenCaptureKit)
import AuthenticationServices
import SwiftUI

struct ChecklistMenuView: View {
    private static let appleEmailDefaultsKey = "com.buildbarber.sdk.testerEmail"

    let test: BuildBarberTest
    @ObservedObject var sessionManager: BuildBarberSessionManager
    var initialFeedback = ""
    let onSubmit: (String?, String, String, [String]) async throws -> Void

    @State private var testerEmail = UserDefaults.standard.string(forKey: Self.appleEmailDefaultsKey) ?? ""
    @State private var signInError: String?
    @State private var feedback: String
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var errorDetails: String?
    @State private var showingErrorDetails = false
    @Environment(\.dismiss) private var dismiss

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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "gift.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reward.description)
                                    .font(.headline)
                            }
                        }
                        Text("Sign in below for reward")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.45)))
                    .padding(.horizontal)
                }

                List(test.checklist, id: \.key) { item in
                    Button {
                        sessionManager.toggleChecklistItem(key: item.key)
                    } label: {
                        Label(item.label, systemImage: sessionManager.checkedChecklistItemKeys.contains(item.key) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(.primary)
                    }
                }
                
                //Text("Sign in with Apple to fill in your email address.").font(.caption)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                           let email = credential.email ?? Self.email(fromIdentityToken: credential.identityToken) {
                            testerEmail = email
                            UserDefaults.standard.set(email, forKey: Self.appleEmailDefaultsKey)
                            signInError = nil
                        } else if testerEmail.isEmpty {
                            signInError = "Apple did not provide an email address. Enter it below to continue."
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

                if let signInError {
                    Text(signInError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                TextField("Tester email", text: $testerEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                TextEditor(text: $feedback)
                    .frame(minHeight: 70, maxHeight: 70)
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
                    .disabled(isSubmitting)

                    Button("Fail") {
                        submit(outcome: "fail")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                } else {
                    Button("Submit feedback") {
                        submit(outcome: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .navigationTitle(test.title)
            .navigationBarTitleDisplayMode(.inline)
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
