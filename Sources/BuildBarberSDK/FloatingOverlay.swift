#if canImport(UIKit)
import SwiftUI
import UIKit

private struct FloatingClipboardButton: View {
    let onTap: () -> Void
    @State private var isWiggling = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.yellow)
                .symbolEffect(.wiggle, isActive: isWiggling)
                .frame(width: 60, height: 60)
                .background(.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Session menu")
        .task {
            while !Task.isCancelled {
                isWiggling = true
                do {
                    try await Task.sleep(for: .milliseconds(700))
                    isWiggling = false
                    try await Task.sleep(for: .milliseconds(4_300))
                } catch {
                    return
                }
            }
        }
    }
}

/// A window that only intercepts touches that land on its button.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === rootViewController?.view ? nil : view
    }
}

@MainActor
final class FloatingOverlay {
    private var window: PassthroughWindow?
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) { self.onTap = onTap }

    func show(in scene: UIWindowScene) {
        guard window == nil else { return }
        let size: CGFloat = 40
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root

        let host = UIHostingController(rootView: FloatingClipboardButton(onTap: onTap))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        root.addChild(host)
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        // Sits just below the status bar area (safe area top), centered.
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            host.view.topAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.topAnchor, constant: 4),
            host.view.widthAnchor.constraint(equalToConstant: size),
            host.view.heightAnchor.constraint(equalToConstant: size)
        ])
        window.isHidden = false
        self.window = window
    }

    /// The overlay's root controller, used to present the menu above the app.
    var presenter: UIViewController? { window?.rootViewController }

    /// Overlay window and root view for drawing tap indicators.
    var overlayWindow: UIWindow? { window }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}
#endif
