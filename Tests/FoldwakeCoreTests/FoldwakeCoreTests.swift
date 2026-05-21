import Foundation
import Testing
@testable import FoldwakeCore

@Test func pmsetParserDetectsSleepDisabled() {
    let output = """
    System-wide power settings:
     SleepDisabled          1
     displaysleep           10
    """

    #expect(PMSetSleepStateParser.systemSleepDisabled(in: output))
}

@Test func pmsetParserIgnoresSleepDisabledZero() {
    let output = """
    System-wide power settings:
     SleepDisabled          0
     disksleep              10
    """

    #expect(!PMSetSleepStateParser.systemSleepDisabled(in: output))
}

@Test func batteryGuardOnlyRestoresOnLowBattery() {
    #expect(BatteryGuardPolicy.shouldRestoreNormalSleep(
        batteryGuardEnabled: true,
        snapshot: PowerSnapshot(isOnAC: false, batteryPercent: 20),
        lowBatteryPercent: 20
    ))

    #expect(!BatteryGuardPolicy.shouldRestoreNormalSleep(
        batteryGuardEnabled: true,
        snapshot: PowerSnapshot(isOnAC: true, batteryPercent: 5),
        lowBatteryPercent: 20
    ))

    #expect(!BatteryGuardPolicy.shouldRestoreNormalSleep(
        batteryGuardEnabled: false,
        snapshot: PowerSnapshot(isOnAC: false, batteryPercent: 5),
        lowBatteryPercent: 20
    ))
}

@Test func statusLineIncludesSystemSleepState() {
    let status = StatusLineFormatter.menuStatus(
        isBlocked: false,
        snapshot: PowerSnapshot(isOnAC: true, batteryPercent: 80),
        systemSleepDisabled: true
    )

    #expect(status == "Normal · AC 80% · System sleep disabled")
}

@Test func launchAgentPlistUsesAppBundleAndProductIdentifier() throws {
    let data = try LaunchAgentPlist.makeData(appPath: "/Applications/Foldwake.app")
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

    #expect(plist["Label"] as? String == AppIdentity.bundleIdentifier)
    #expect(plist["RunAtLoad"] as? Bool == true)
    #expect(plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "/Applications/Foldwake.app"])
}
