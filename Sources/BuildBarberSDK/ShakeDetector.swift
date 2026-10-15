#if canImport(UIKit) && canImport(ScreenCaptureKit)
import CoreMotion
import Foundation

/// Detects a phone shake from accelerometer data, without needing the host app's responder chain.
@MainActor
final class ShakeDetector {
    private let motion = CMMotionManager()
    private var lastShake = Date.distantPast
    private var onShake: (@MainActor () -> Void)?

    // Acceleration (in g) above which a movement counts as a shake.
    private let threshold = 2.2
    private let cooldown: TimeInterval = 2

    func start(onShake: @escaping @MainActor () -> Void) {
        self.onShake = onShake
        guard !motion.isAccelerometerActive, motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 30.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            MainActor.assumeIsolated { self.handle(magnitude) }
        }
    }

    private func handle(_ magnitude: Double) {
        guard magnitude > threshold, Date().timeIntervalSince(lastShake) > cooldown else { return }
        lastShake = Date()
        onShake?()
    }
}
#endif
