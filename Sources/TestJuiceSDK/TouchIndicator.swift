#if canImport(UIKit)
import ObjectiveC
import UIKit

/// Draws a semi-transparent orange dot under every finger so taps are visible in the recording.
///
/// Touches are observed by swizzling `UIApplication.sendEvent(_:)`. To make sure the dot reaches the
/// video before whatever a tap triggers (for example a crash), the touch-up of a quick tap is held
/// back until the dot has been on screen for `minimumVisibleTime`.
@MainActor
final class TouchIndicator {
    static let shared = TouchIndicator()

    static let dotDiameter: CGFloat = 100
    private static let tapMovementTolerance: CGFloat = 10

    private struct Tracked {
        let dot: UIView
        let startTime: TimeInterval
        let startLocation: CGPoint
    }

    private weak var hostView: UIView?
    private weak var ignoredWindow: UIWindow?
    private var minimumVisibleTime: TimeInterval = 0
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private(set) var isEnabled = false

    private init() {}

    /// Starts drawing dots into `hostView`. Touches in `ignoredWindow` (the SDK's own UI) are skipped.
    func start(in hostView: UIView, ignoring ignoredWindow: UIWindow?, minimumVisibleTime: TimeInterval) {
        UIApplication.installTouchObserver()
        self.hostView = hostView
        self.ignoredWindow = ignoredWindow
        self.minimumVisibleTime = max(0, minimumVisibleTime)
        isEnabled = true
    }

    func stop() {
        isEnabled = false
        tracked.values.forEach { $0.dot.removeFromSuperview() }
        tracked.removeAll()
    }

    fileprivate func handle(_ event: UIEvent) {
        guard isEnabled, event.type == .touches, let hostView, let touches = event.allTouches else { return }
        for touch in touches {
            if let window = touch.window, window === ignoredWindow || window is PassthroughWindow { continue }
            let key = ObjectIdentifier(touch)
            let location = touch.location(in: hostView)
            switch touch.phase {
            case .began:
                began(key, at: location, in: hostView)
            case .moved, .stationary:
                tracked[key]?.dot.center = location
            case .ended:
                ended(key, at: location)
            case .cancelled:
                finish(key)
            default:
                break
            }
        }
    }

    private func began(_ key: ObjectIdentifier, at location: CGPoint, in hostView: UIView) {
        tracked[key]?.dot.removeFromSuperview()
        let size = Self.dotDiameter
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        dot.center = location
        dot.layer.cornerRadius = size / 2
        dot.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.5)
        dot.isUserInteractionEnabled = false
        hostView.addSubview(dot)
        tracked[key] = Tracked(dot: dot, startTime: ProcessInfo.processInfo.systemUptime, startLocation: location)
        // Commit now so the dot is composited before the app reacts to this touch.
        CATransaction.flush()
    }

    private func ended(_ key: ObjectIdentifier, at location: CGPoint) {
        if let item = tracked[key], minimumVisibleTime > 0 {
            let moved = hypot(location.x - item.startLocation.x, location.y - item.startLocation.y)
            let remaining = minimumVisibleTime - (ProcessInfo.processInfo.systemUptime - item.startTime)
            if moved <= Self.tapMovementTolerance, remaining > 0 {
                // Blocks briefly so the app handles the tap only after the dot has been captured.
                Thread.sleep(forTimeInterval: remaining)
            }
        }
        finish(key)
    }

    private func finish(_ key: ObjectIdentifier) {
        guard let item = tracked.removeValue(forKey: key) else { return }
        UIView.animate(withDuration: 0.25, animations: { item.dot.alpha = 0 }, completion: { _ in
            item.dot.removeFromSuperview()
        })
    }
}

private nonisolated(unsafe) var touchObserverInstalled = false

extension UIApplication {
    fileprivate static func installTouchObserver() {
        guard !touchObserverInstalled,
              let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
              let swizzled = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.bb_sendEvent(_:)))
        else { return }
        method_exchangeImplementations(original, swizzled)
        touchObserverInstalled = true
    }

    // After the exchange, this runs in place of `sendEvent(_:)` and the call below reaches the original.
    @objc fileprivate func bb_sendEvent(_ event: UIEvent) {
        MainActor.assumeIsolated { TouchIndicator.shared.handle(event) }
        bb_sendEvent(event)
    }
}
#endif
