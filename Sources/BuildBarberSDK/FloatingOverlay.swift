#if canImport(UIKit)
import UIKit

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

        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "pencil.and.list.clipboard")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .black
        config.baseForegroundColor = .yellow
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onTap() })
        button.accessibilityLabel = "Session menu"
        button.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(button)
        // Sits just below the status bar area (safe area top), centered.
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            button.topAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.topAnchor, constant: 4),
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
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
