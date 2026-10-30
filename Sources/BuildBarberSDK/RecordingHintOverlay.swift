#if canImport(UIKit)
import SwiftUI
import UIKit

private struct HintArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.7, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.7, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.3, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.3, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct RecordingHintView: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack {
                HintArrow()
                    .fill(Color.white)
                    .overlay(HintArrow().stroke(Color.black, lineWidth: 2))
                    .frame(width: 44, height: 56)
                    .padding(.leading, 56)
                Spacer()
            }
            Text(message)
                .font(.headline)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(white: 0.85))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }
}

/// Bottom panel shown while the system screen-recording permission prompt is up.
@MainActor
final class RecordingHintOverlay {
    private var window: UIWindow?

    static func message(hasReward: Bool) -> String {
        hasReward ? "Record for reward" : "Recording help us fix more bugs"
    }

    func show(in scene: UIWindowScene, hasReward: Bool) {
        guard window == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert - 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: RecordingHintView(message: Self.message(hasReward: hasReward)))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}
#endif
