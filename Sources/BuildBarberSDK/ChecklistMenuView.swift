#if canImport(UIKit)
import SwiftUI

@MainActor
final class SessionModel: ObservableObject {
    @Published var items: [ChecklistEntry] = []
    @Published var feedback = ""
}

struct ChecklistMenuView: View {
    @ObservedObject var model: SessionModel
    let onContinue: () -> Void
    let onEnd: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                List(model.items) { item in
                    HStack {
                        Image(systemName: item.isTicked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isTicked ? .green : .secondary)
                        Text(item.title)
                        Spacer()
                        Text(item.isTicked ? "Ticked" : "Not yet ticked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                TextEditor(text: $model.feedback)
                    .frame(minHeight: 100, maxHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                    .padding(.horizontal)
                HStack {
                    Button("Continue", action: onContinue).buttonStyle(.bordered)
                    Spacer()
                    Button("End", role: .destructive, action: onEnd).buttonStyle(.borderedProminent)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
