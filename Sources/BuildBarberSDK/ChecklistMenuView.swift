#if canImport(UIKit)
import AuthenticationServices
import SwiftUI

struct ChecklistMenuView: View {
    private static let appleEmailDefaultsKey = "com.buildbarber.sdk.testerEmail"

    let test: BuildBarberTest
    @ObservedObject var sessionManager: BuildBarberSessionManager
    let onSubmit: (String?, String, String, [String]) async throws -> Void

    @State private var testerEmail = UserDefaults.standard.string(forKey: Self.appleEmailDefaultsKey) ?? ""
    @State private var signInError: String?
    @State private var feedback = ""
    @State private var isSubmitting = false
    @State private var submissionError: String?

    private var allItemsChecked: Bool {
        test.checklist.allSatisfy { sessionManager.checkedChecklistItemKeys.contains($0.key) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(test.instructions)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                List(test.checklist, id: \.key) { item in
                    Button {
                        sessionManager.toggleChecklistItem(key: item.key)
                    } label: {
                        Label(item.label, systemImage: sessionManager.checkedChecklistItemKeys.contains(item.key) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(.primary)
                    }
                }
                Text("Sign in with Apple to fill in your email address.")
                    .font(.caption)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                           let email = credential.email {
                            testerEmail = email
                            UserDefaults.standard.set(email, forKey: Self.appleEmailDefaultsKey)
                            signInError = nil
                        } else if testerEmail.isEmpty {
                            signInError = "Apple did not provide an email address. Enter it below to continue."
                        }
                    case .failure(let error):
                        signInError = error.localizedDescription
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
                    .frame(minHeight: 100, maxHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                    .padding(.horizontal)

                if let submissionError {
                    Text(submissionError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack {
                    if test.showPassFailButtons {
                        Button("Pass") {
                            submit(outcome: "pass")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!allItemsChecked || isSubmitting)

                        Button("Fail") {
                            submit(outcome: "fail")
                        }
                        .buttonStyle(.bordered)
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    } else {
                        Button("Submit feedback") {
                            submit(outcome: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle(test.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit(outcome: String?) {
        isSubmitting = true
        submissionError = nil
        Task {
            do {
                try await onSubmit(
                    outcome,
                    testerEmail,
                    feedback,
                    test.checklist.filter { sessionManager.checkedChecklistItemKeys.contains($0.key) }.map(\.key))
            } catch {
                submissionError = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
#endif
