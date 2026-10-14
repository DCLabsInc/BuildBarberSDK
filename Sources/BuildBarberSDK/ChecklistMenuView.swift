#if canImport(UIKit)
import SwiftUI

struct ChecklistMenuView: View {
    let test: BuildBarberTest
    let onSubmit: (String?, String, String, [String]) async throws -> Void

    @State private var checkedItems = Set<String>()
    @State private var testerEmail = ""
    @State private var feedback = ""
    @State private var isSubmitting = false
    @State private var submissionError: String?

    private var allItemsChecked: Bool {
        test.checklist.allSatisfy { checkedItems.contains($0.key) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(test.instructions)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                List(test.checklist, id: \.key) { item in
                    Button {
                        if checkedItems.contains(item.key) {
                            checkedItems.remove(item.key)
                        } else {
                            checkedItems.insert(item.key)
                        }
                    } label: {
                        Label(item.label, systemImage: checkedItems.contains(item.key) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(.primary)
                    }
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
                    test.checklist.filter { checkedItems.contains($0.key) }.map(\.key))
            } catch {
                submissionError = "The result could not be submitted. Please try again."
                isSubmitting = false
            }
        }
    }
}
#endif
