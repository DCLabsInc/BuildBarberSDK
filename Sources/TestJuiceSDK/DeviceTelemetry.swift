import Foundation

public struct TestJuiceDeviceTelemetry: Encodable, Sendable, Equatable {
    public let deviceModel: String?
    public let osVersion: String?
    public let networkType: String?
    public let batteryLevel: Int?
    public let appVersion: String?
    public let localeLanguage: String?
    public let deviceMemoryMb: Int?
    public let screenSize: String?

    public init(
        deviceModel: String? = nil,
        osVersion: String? = nil,
        networkType: String? = nil,
        batteryLevel: Int? = nil,
        appVersion: String? = nil,
        localeLanguage: String? = nil,
        deviceMemoryMb: Int? = nil,
        screenSize: String? = nil
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.networkType = networkType
        self.batteryLevel = batteryLevel
        self.appVersion = appVersion
        self.localeLanguage = localeLanguage
        self.deviceMemoryMb = deviceMemoryMb
        self.screenSize = screenSize
    }

    private enum CodingKeys: String, CodingKey {
        case deviceModel
        case osVersion
        case networkType
        case batteryLevel
        case appVersion
        case localeLanguage
        case deviceMemoryMb
        case screenSize
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(deviceModel, forKey: .deviceModel)
        try container.encodeIfPresent(osVersion, forKey: .osVersion)
        try container.encodeIfPresent(networkType, forKey: .networkType)
        try container.encodeIfPresent(batteryLevel, forKey: .batteryLevel)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(localeLanguage, forKey: .localeLanguage)
        try container.encodeIfPresent(deviceMemoryMb, forKey: .deviceMemoryMb)
        try container.encodeIfPresent(screenSize, forKey: .screenSize)
    }
}

#if canImport(Network) && canImport(UIKit)
import Network
import UIKit

extension TestJuiceDeviceTelemetry {
    @MainActor
    static func collect() async -> Self {
        let device = UIDevice.current
        let wasBatteryMonitoringEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = device.batteryLevel
        device.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled

        let bounds = UIScreen.main.bounds
        let diagonal = hypot(bounds.width, bounds.height)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let networkType = await networkType()

        return Self(
            deviceModel: device.model,
            osVersion: device.systemVersion,
            networkType: networkType,
            batteryLevel: batteryLevel >= 0
                ? min(100, max(0, Int((batteryLevel * 100).rounded())))
                : nil,
            appVersion: appVersion,
            localeLanguage: Locale.current.language.languageCode?.identifier,
            deviceMemoryMb: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
            screenSize: "\(Int(diagonal.rounded())) pt")
    }

    private static func networkType() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let networkType: String?
                if path.usesInterfaceType(.wifi) {
                    networkType = "WiFi"
                } else if path.usesInterfaceType(.cellular) {
                    networkType = "Cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    networkType = "Ethernet"
                } else if path.status == .satisfied {
                    networkType = "Other"
                } else {
                    networkType = nil
                }
                monitor.cancel()
                continuation.resume(returning: networkType)
            }
            monitor.start(queue: DispatchQueue(label: "com.testjuice.sdk.network-monitor"))
        }
    }
}
#endif
