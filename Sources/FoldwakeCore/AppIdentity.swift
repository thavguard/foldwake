import Foundation

@objc(FoldwakeHelperProtocol)
public protocol FoldwakeHelperProtocol: NSObjectProtocol {
    func setLidSleepBlocked(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
}

public enum AppIdentity {
    public static let displayName = "Foldwake"
    public static let bundleIdentifier = "io.github.thavguard.foldwake"
    public static let helperLabel = "io.github.thavguard.foldwake.helper"
    public static let helperPlistName = "\(helperLabel).plist"
}

public enum DefaultsKey {
    public static let totalBlock = "totalBlock"
    public static let batteryGuard = "batteryGuard"
    public static let lowBatteryPercent = "lowBatteryPercent"
}

public struct PowerSnapshot: Equatable, Sendable {
    public let isOnAC: Bool
    public let batteryPercent: Int

    public init(isOnAC: Bool, batteryPercent: Int) {
        self.isOnAC = isOnAC
        self.batteryPercent = batteryPercent
    }
}

public struct ClamshellReadiness: Equatable, Sendable {
    public let isOnAC: Bool
    public let externalDisplayCount: Int

    public init(isOnAC: Bool, externalDisplayCount: Int) {
        self.isOnAC = isOnAC
        self.externalDisplayCount = externalDisplayCount
    }

    public var isReady: Bool {
        isOnAC && externalDisplayCount > 0
    }

    public var blockingReasons: [String] {
        var reasons: [String] = []
        if !isOnAC {
            reasons.append("power")
        }
        if externalDisplayCount == 0 {
            reasons.append("external display")
        }
        return reasons
    }

    public var shortStatus: String {
        if isReady {
            return "Clamshell ready"
        }
        return "Clamshell needs \(humanList(blockingReasons))"
    }

    public var failureMessage: String {
        """
        Foldwake can keep a Mac awake with the lid closed only in macOS closed-display mode.

        Before enabling Block Mac Sleep, connect power, an external display, and an external keyboard or mouse. Current blockers: \(humanList(blockingReasons)).
        """
    }

    private func humanList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            return "\(items.dropLast().joined(separator: ", ")), and \(items.last ?? "")"
        }
    }
}

public enum PMSetSleepStateParser {
    public static func systemSleepDisabled(in output: String) -> Bool {
        output
            .split(separator: "\n")
            .contains { line in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
            }
    }
}

public enum BatteryGuardPolicy {
    public static func shouldRestoreNormalSleep(
        batteryGuardEnabled: Bool,
        snapshot: PowerSnapshot,
        lowBatteryPercent: Int
    ) -> Bool {
        batteryGuardEnabled
            && !snapshot.isOnAC
            && snapshot.batteryPercent <= lowBatteryPercent
    }
}

public enum StatusLineFormatter {
    public static func menuStatus(
        isBlocked: Bool,
        snapshot: PowerSnapshot,
        readiness: ClamshellReadiness
    ) -> String {
        let source = snapshot.isOnAC ? "AC" : "Battery"
        return "\(isBlocked ? "Protected" : "Normal") · \(source) \(snapshot.batteryPercent)% · \(readiness.shortStatus)"
    }
}

public enum LaunchAgentPlist {
    public static func makeData(appPath: String) throws -> Data {
        let plist: [String: Any] = [
            "Label": AppIdentity.bundleIdentifier,
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
