import AppKit
import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import FoldwakeCore
import ServiceManagement

private enum FoldwakeError: LocalizedError {
    case powerAssertionFailed(IOReturn)
    case launchAgentPathUnavailable
    case helperRequiresApproval
    case helperUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .powerAssertionFailed(let code):
            "Could not create macOS power assertion: \(code)"
        case .launchAgentPathUnavailable:
            "Foldwake must be launched from the built .app before enabling login startup."
        case .helperRequiresApproval:
            "Enable FoldwakeHelper in System Settings > Login Items, then try again."
        case .helperUnavailable(let message):
            message
        }
    }
}

private final class PowerController {
    private var assertionIDs: [IOPMAssertionID] = []

    var totalBlockEnabled: Bool {
        !assertionIDs.isEmpty
    }

    func enableTotalBlock() throws {
        guard assertionIDs.isEmpty else { return }

        let assertions: [(CFString, String)] = [
            (kIOPMAssertionTypeNoIdleSleep as CFString, "Foldwake blocks idle sleep"),
            (kIOPMAssertionTypePreventSystemSleep as CFString, "Foldwake blocks system sleep")
        ]

        var created: [IOPMAssertionID] = []
        for (type, reason) in assertions {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                for createdID in created {
                    IOPMAssertionRelease(createdID)
                }
                throw FoldwakeError.powerAssertionFailed(result)
            }
            created.append(id)
        }

        assertionIDs = created
    }

    func disableTotalBlock() {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs.removeAll()
    }

}

private func systemSleepDisabled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return false
    }

    guard process.terminationStatus == 0 else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return false }
    return PMSetSleepStateParser.systemSleepDisabled(in: output)
}

private func lidClosed() -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    guard let property = IORegistryEntryCreateCFProperty(
        service,
        "AppleClamshellState" as CFString,
        kCFAllocatorDefault,
        0
    )?.takeRetainedValue() else {
        return nil
    }

    return property as? Bool
}

private func sleepDisplaysNow() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["displaysleepnow"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        NSLog("Foldwake could not request display sleep: %@", error.localizedDescription)
    }
}

private func wakeDisplayForLidOpen() {
    var assertionID = IOPMAssertionID(0)
    let result = IOPMAssertionDeclareUserActivity(
        "Foldwake lid opened" as CFString,
        kIOPMUserActiveLocal,
        &assertionID
    )
    if result == kIOReturnSuccess {
        IOPMAssertionRelease(assertionID)
    } else {
        NSLog("Foldwake could not declare lid-open user activity: %d", result)
    }
}

private final class XPCContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Void = ()) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

private func makeXPCErrorHandler(gate: XPCContinuationGate? = nil) -> (Error) -> Void {
    { error in
        NSLog("FoldwakeHelper XPC error: %@", error.localizedDescription)
        gate?.resume(throwing: FoldwakeError.helperUnavailable(error.localizedDescription))
    }
}

private func makeLidSleepReplyHandler(
    gate: XPCContinuationGate
) -> (Bool, String?) -> Void {
    { ok, message in
        if ok {
            gate.resume()
        } else {
            gate.resume(throwing: FoldwakeError.helperUnavailable(message ?? "FoldwakeHelper failed."))
        }
    }
}

@MainActor
private final class PrivilegedHelperClient {
    private var connection: NSXPCConnection?

    var service: SMAppService {
        SMAppService.daemon(plistName: AppIdentity.helperPlistName)
    }

    var status: SMAppService.Status {
        service.status
    }

    func ensureEnabled() throws {
        let service = service
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            throw FoldwakeError.helperRequiresApproval
        default:
            try service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                throw FoldwakeError.helperRequiresApproval
            }
            guard service.status == .enabled else {
                throw FoldwakeError.helperUnavailable("FoldwakeHelper status is \(service.status).")
            }
        }
    }

    func installOrRepair() async throws {
        connection?.invalidate()
        connection = nil

        let service = service
        if service.status != .notRegistered && service.status != .notFound {
            do {
                try await service.unregister()
            } catch {
                NSLog("FoldwakeHelper unregister during repair failed: %@", error.localizedDescription)
            }
        }

        try service.register()
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            throw FoldwakeError.helperRequiresApproval
        }
        guard service.status == .enabled else {
            throw FoldwakeError.helperUnavailable("FoldwakeHelper status is \(service.status).")
        }
    }

    func setLidSleepBlocked(_ enabled: Bool) async throws {
        try ensureEnabled()
        let connection = connection ?? makeConnection()
        self.connection = connection

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = XPCContinuationGate(continuation: continuation)
                guard let proxy = connection.remoteObjectProxyWithErrorHandler(makeXPCErrorHandler(gate: gate)) as? FoldwakeHelperProtocol else {
                    gate.resume(throwing: FoldwakeError.helperUnavailable("Could not create FoldwakeHelper XPC proxy."))
                    return
                }

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                    gate.resume(throwing: FoldwakeError.helperUnavailable("FoldwakeHelper did not reply within 3 seconds."))
                }

                proxy.setLidSleepBlocked(enabled, withReply: makeLidSleepReplyHandler(gate: gate))
            }
        } catch {
            connection.invalidate()
            self.connection = nil
            throw error
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: AppIdentity.helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FoldwakeHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        connection.resume()
        return connection
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let power = PowerController()
    private let helper = PrivilegedHelperClient()
    private let defaults = UserDefaults.standard
    private var batteryTimer: Timer?
    private var powerStateTimer: Timer?
    private var lidTimer: Timer?
    private var isReconcilingPowerState = false
    private var isTerminating = false
    private var knownSystemSleepDisabled = false
    private var lastLidClosed: Bool?
    private var lastDisplaySleepRequest = Date.distantPast
    private let statusItemMenu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let helperStatusItem = NSMenuItem(title: "", action: #selector(openLoginItemsSettingsFromMenu), keyEquivalent: ",")
    private let installHelperItem = NSMenuItem(title: "Install or Repair Helper...", action: #selector(enableHelperFromMenu), keyEquivalent: "i")
    private let blockSleepItem = NSMenuItem(title: "Block Mac Sleep", action: #selector(toggleTotalBlockFromMenu), keyEquivalent: "b")
    private let batteryGuardItem = NSMenuItem(title: "Battery Guard", action: #selector(toggleBatteryGuardFromMenu), keyEquivalent: "g")
    private let startAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleStartAtLoginFromMenu), keyEquivalent: "l")
    private let restoreSleepItem = NSMenuItem(title: "Restore Normal Sleep", action: #selector(restoreNormalSleepFromMenu), keyEquivalent: "r")
    private let quitItem = NSMenuItem(title: "Quit Foldwake", action: #selector(quitFromMenu), keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        defaults.register(defaults: [
            DefaultsKey.lowBatteryPercent: 20
        ])
        knownSystemSleepDisabled = systemSleepDisabled()

        configureStatusItem()
        configureMenu()
        restorePreviousState()
        startBatteryMonitor()
        startPowerStateReconciler()
        startLidMonitor()
        render()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        Task { @MainActor in
            await restoreNormalSleepForTermination()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: AppIdentity.displayName)
        button.image?.isTemplate = true
        statusItem.menu = statusItemMenu
    }

    private func configureMenu() {
        statusMenuItem.isEnabled = false

        blockSleepItem.target = self
        batteryGuardItem.target = self
        startAtLoginItem.target = self
        restoreSleepItem.target = self
        helperStatusItem.target = self
        installHelperItem.target = self
        quitItem.target = self

        statusItemMenu.addItem(statusMenuItem)
        statusItemMenu.addItem(helperStatusItem)
        statusItemMenu.addItem(.separator())
        statusItemMenu.addItem(installHelperItem)
        statusItemMenu.addItem(blockSleepItem)
        statusItemMenu.addItem(batteryGuardItem)
        statusItemMenu.addItem(startAtLoginItem)
        statusItemMenu.addItem(.separator())
        statusItemMenu.addItem(restoreSleepItem)
        statusItemMenu.addItem(.separator())
        statusItemMenu.addItem(quitItem)
    }

    private func restorePreviousState() {
        guard defaults.bool(forKey: DefaultsKey.totalBlock) else {
            return
        }

        do {
            try power.enableTotalBlock()
            Task { @MainActor in
                do {
                    try await helper.setLidSleepBlocked(true)
                } catch {
                    power.disableTotalBlock()
                    defaults.set(false, forKey: DefaultsKey.totalBlock)
                    showError(error)
                }
                render()
            }
        } catch {
            defaults.set(false, forKey: DefaultsKey.totalBlock)
            showError(error)
        }
    }

    private func startBatteryMonitor() {
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.enforceBatteryGuard()
            }
        }
        enforceBatteryGuard()
    }

    private func startPowerStateReconciler() {
        powerStateTimer?.invalidate()
        powerStateTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.reconcilePowerState(showErrors: false)
            }
        }
        Task { @MainActor in
            await reconcilePowerState(showErrors: false)
        }
    }

    private func startLidMonitor() {
        lidTimer?.invalidate()
        lastLidClosed = lidClosed()
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleLidState()
            }
        }
        handleLidState()
    }

    private func handleLidState() {
        guard let isClosed = lidClosed() else { return }
        let wasClosed = lastLidClosed
        lastLidClosed = isClosed

        guard effectiveSleepBlockEnabled else { return }

        if isClosed {
            let shouldRequestDisplaySleep = wasClosed != true
                || Date().timeIntervalSince(lastDisplaySleepRequest) > 10
            if shouldRequestDisplaySleep {
                lastDisplaySleepRequest = Date()
                sleepDisplaysNow()
            }
        } else if wasClosed == true {
            wakeDisplayForLidOpen()
        }
    }

    private func reconcilePowerState(showErrors: Bool) async {
        guard !isReconcilingPowerState else { return }
        isReconcilingPowerState = true
        defer {
            isReconcilingPowerState = false
            render()
        }

        let shouldBlockSleep = defaults.bool(forKey: DefaultsKey.totalBlock)
        let sleepDisabled = systemSleepDisabled()
        knownSystemSleepDisabled = sleepDisabled
        do {
            if shouldBlockSleep {
                try power.enableTotalBlock()
                if !sleepDisabled {
                    try await helper.setLidSleepBlocked(true)
                    knownSystemSleepDisabled = true
                }
            } else {
                power.disableTotalBlock()
                if sleepDisabled {
                    try await helper.setLidSleepBlocked(false)
                    knownSystemSleepDisabled = false
                }
            }
        } catch {
            if !shouldBlockSleep {
                power.disableTotalBlock()
            }
            if showErrors {
                showError(error)
            }
        }
    }

    private func enforceBatteryGuard() {
        let snapshot = powerSnapshot()
        guard BatteryGuardPolicy.shouldRestoreNormalSleep(
            batteryGuardEnabled: defaults.bool(forKey: DefaultsKey.batteryGuard),
            snapshot: snapshot,
            lowBatteryPercent: defaults.integer(forKey: DefaultsKey.lowBatteryPercent)
        ) else {
            render()
            return
        }

        restoreNormalSleep(showErrors: false)
    }

    @objc private func toggleTotalBlockFromMenu() {
        if effectiveSleepBlockEnabled {
            restoreNormalSleep(showErrors: true)
        } else {
            enableTotalBlock()
        }
    }

    @objc private func enableHelperFromMenu() {
        Task { @MainActor in
            do {
                try await helper.installOrRepair()
            } catch {
                showError(error)
            }
            render()
        }
    }

    @objc private func openLoginItemsSettingsFromMenu() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func toggleBatteryGuardFromMenu() {
        defaults.set(!defaults.bool(forKey: DefaultsKey.batteryGuard), forKey: DefaultsKey.batteryGuard)
        enforceBatteryGuard()
        render()
    }

    @objc private func toggleStartAtLoginFromMenu() {
        do {
            if isStartAtLoginEnabled() {
                try removeLaunchAgent()
            } else {
                try installLaunchAgent()
            }
        } catch {
            showError(error)
        }
        render()
    }

    @objc private func restoreNormalSleepFromMenu() {
        restoreNormalSleep(showErrors: true)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func enableTotalBlock() {
        Task { @MainActor in
            do {
                try power.enableTotalBlock()
                try await helper.setLidSleepBlocked(true)
                knownSystemSleepDisabled = true
                defaults.set(true, forKey: DefaultsKey.totalBlock)
                await reconcilePowerState(showErrors: false)
            } catch {
                power.disableTotalBlock()
                defaults.set(false, forKey: DefaultsKey.totalBlock)
                showError(error)
            }
            render()
        }
    }

    private func restoreNormalSleep(showErrors: Bool) {
        power.disableTotalBlock()
        defaults.set(false, forKey: DefaultsKey.totalBlock)
        Task { @MainActor in
            do {
                try await helper.setLidSleepBlocked(false)
                knownSystemSleepDisabled = false
                await reconcilePowerState(showErrors: false)
            } catch {
                if showErrors {
                    showError(error)
                }
            }
            render()
        }
    }

    private func restoreNormalSleepForTermination() async {
        power.disableTotalBlock()
        defaults.set(false, forKey: DefaultsKey.totalBlock)
        do {
            try await helper.setLidSleepBlocked(false)
            knownSystemSleepDisabled = false
        } catch {
            NSLog("Foldwake could not restore lid sleep during termination: %@", error.localizedDescription)
        }
    }

    private var effectiveSleepBlockEnabled: Bool {
        power.totalBlockEnabled || knownSystemSleepDisabled
    }

    private func render() {
        let isBlocked = effectiveSleepBlockEnabled
        let snapshot = powerSnapshot()
        statusMenuItem.title = StatusLineFormatter.menuStatus(isBlocked: isBlocked, snapshot: snapshot)
        helperStatusItem.title = "Helper: \(helperStatusTitle())"
        blockSleepItem.state = isBlocked ? .on : .off
        batteryGuardItem.state = defaults.bool(forKey: DefaultsKey.batteryGuard) ? .on : .off
        startAtLoginItem.state = isStartAtLoginEnabled() ? .on : .off
        restoreSleepItem.isEnabled = isBlocked
        installHelperItem.isHidden = helper.status == .enabled
        blockSleepItem.isEnabled = helper.status == .enabled
    }

    private func helperStatusTitle() -> String {
        switch helper.status {
        case .enabled:
            "Enabled"
        case .requiresApproval:
            "Needs Approval"
        case .notRegistered:
            "Not Installed"
        case .notFound:
            "Not Found"
        @unknown default:
            "Unknown"
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Foldwake"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
        render()
    }

    private func powerSnapshot() -> PowerSnapshot {
        PowerSnapshot(isOnAC: isOnACPower(), batteryPercent: currentBatteryPercent())
    }

    private func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return source == kIOPSACPowerValue
    }

    private func currentBatteryPercent() -> Int {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return 100
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int,
                  max > 0
            else {
                continue
            }
            return Int((Double(current) / Double(max) * 100).rounded())
        }

        return 100
    }

    private func launchAgentDirectory(create: Bool) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func launchAgentURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(AppIdentity.bundleIdentifier).plist")
    }

    private func prepareLaunchAgentURL() throws -> URL {
        try launchAgentDirectory(create: true)
            .appendingPathComponent("\(AppIdentity.bundleIdentifier).plist")
    }

    private func installLaunchAgent() throws {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            throw FoldwakeError.launchAgentPathUnavailable
        }

        let data = try LaunchAgentPlist.makeData(appPath: appPath)
        try data.write(to: try prepareLaunchAgentURL(), options: .atomic)
    }

    private func removeLaunchAgent() throws {
        let url = launchAgentURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func isStartAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL().path)
    }
}

@main
enum FoldwakeMain {
    @MainActor
    static func main() async {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}
