import Foundation
import FoldwakeCore
import Security
import Darwin

private enum CodesignCheckError: Error {
    case message(String)
}

private struct CodesignCheck {
    static func codeSigningMatches(pid: pid_t) throws -> Bool {
        let selfInfo = try signingInfoForSelf()
        let clientInfo = try signingInfo(forPID: pid)
        return !selfInfo.certificates.isEmpty
            && !selfInfo.teamIdentifier.isEmpty
            && selfInfo.certificates == clientInfo.certificates
            && selfInfo.teamIdentifier == clientInfo.teamIdentifier
            && clientInfo.identifier == AppIdentity.bundleIdentifier
    }

    private struct SigningInfo {
        let certificates: [SecCertificate]
        let identifier: String
        let teamIdentifier: String
    }

    private static func signingInfoForSelf() throws -> SigningInfo {
        var secCodeSelf: SecCode?
        try execute { SecCodeCopySelf(SecCSFlags(rawValue: 0), &secCodeSelf) }
        guard let secCodeSelf else {
            throw CodesignCheckError.message("SecCodeCopySelf returned no code object")
        }
        return try signingInfo(forSecCode: secCodeSelf)
    }

    private static func signingInfo(forPID pid: pid_t) throws -> SigningInfo {
        var secCode: SecCode?
        try execute {
            SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &secCode)
        }
        guard let secCode else {
            throw CodesignCheckError.message("SecCodeCopyGuestWithAttributes returned no code object")
        }
        return try signingInfo(forSecCode: secCode)
    }

    private static func signingInfo(forSecCode secCode: SecCode) throws -> SigningInfo {
        var staticCode: SecStaticCode?
        try execute { SecCodeCopyStaticCode(secCode, [], &staticCode) }
        guard let staticCode else {
            throw CodesignCheckError.message("SecCodeCopyStaticCode returned no code object")
        }

        try execute {
            SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSCheckNestedCode),
                nil
            )
        }

        var info: CFDictionary?
        try execute {
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        }
        guard let dict = info as? [String: Any] else {
            throw CodesignCheckError.message("SecCodeCopySigningInformation returned no dictionary")
        }
        guard let identifier = dict[kSecCodeInfoIdentifier as String] as? String else {
            throw CodesignCheckError.message("SecCodeCopySigningInformation returned no identifier")
        }
        guard let teamIdentifier = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw CodesignCheckError.message("SecCodeCopySigningInformation returned no team identifier")
        }

        return SigningInfo(
            certificates: dict[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? [],
            identifier: identifier,
            teamIdentifier: teamIdentifier
        )
    }

    private static func execute(_ block: () -> OSStatus) throws {
        let status = block()
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw CodesignCheckError.message(message)
        }
    }
}

private final class HelperDelegate: NSObject, NSXPCListenerDelegate, FoldwakeHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: connection) else {
            NSLog("FoldwakeHelper rejected unauthorized XPC client pid=%d", connection.processIdentifier)
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: FoldwakeHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setLidSleepBlocked(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", enabled ? "1" : "0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply(false, error.localizedDescription)
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus == 0 {
            reply(true, nil)
        } else {
            reply(false, output?.isEmpty == false ? output : "pmset exited with status \(process.terminationStatus)")
        }
    }

    private func isValidClient(connection: NSXPCConnection) -> Bool {
        do {
            return try CodesignCheck.codeSigningMatches(pid: connection.processIdentifier)
        } catch {
            NSLog("FoldwakeHelper code-signing validation failed: %@", "\(error)")
            return false
        }
    }
}

private let delegate = HelperDelegate()
private let listener = NSXPCListener(machServiceName: AppIdentity.helperLabel)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
