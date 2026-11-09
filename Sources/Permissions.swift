import ApplicationServices
import Cocoa

/// Autorisation Accessibilité : l'app la demande elle-même, l'utilisateur n'a qu'à cliquer.
enum Permissions {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Chaque compilation locale change la signature : macOS garde l'interrupteur allumé mais
    /// ne reconnaît plus l'app. On efface donc la seule entrée de Ricochet, pour repartir propre.
    private static func clearStaleEntry() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", id]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Demande à l'ouverture, une seule fois par version installée.
    static func askOncePerBuild() {
        guard !AXIsProcessTrusted() else { return }
        let path = Bundle.main.executablePath ?? ""
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "accessibilityAskedForBuild"
        guard UserDefaults.standard.double(forKey: key) != date else { return }
        UserDefaults.standard.set(date, forKey: key)
        clearStaleEntry()
        prompt()
    }

    /// Ouvre directement les réglages, au moment où l'autorisation est nécessaire.
    static func openSettings() {
        clearStaleEntry()
        prompt()
        NSWorkspace.shared.open(settingsURL)
    }
}
