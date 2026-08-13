import AppKit
import Darwin

/// Full Disk Access detection and the pre-scan prompt.
///
/// macOS has no API to request FDA — the user must add the app in System
/// Settings. Without it, every protected folder the scanner touches fires its
/// own permission popup (Desktop, Documents, Downloads, Photos, …) and
/// FDA-only areas stay unreadable. One FDA grant silences all of it, so we
/// offer that path up front instead of letting the popups rain.
@MainActor
enum FullDiskAccess {
    private static let suppressKey = "SuppressFullDiskAccessPrompt"
    private static var askedThisLaunch = false

    /// Probes paths readable only with Full Disk Access. Directory perms on
    /// these allow reading; only TCC stands in the way, so EPERM ⇒ no FDA.
    static var isGranted: Bool {
        // Reading the system TCC database itself requires Full Disk Access and
        // exists on every Mac, so it's the definitive probe. The user-level
        // paths are fallbacks in case the system one ever behaves differently.
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            ("~/Library/Safari/Bookmarks.plist" as NSString).expandingTildeInPath,
            ("~/Library/Mail" as NSString).expandingTildeInPath,
        ]
        for path in probes {
            let fd = open(path, O_RDONLY)
            let err = errno
            if fd >= 0 {
                close(fd)
                return true
            }
            // ENOENT means the probe file is absent here, not that access was
            // denied — move on to the next probe. Any other error (typically
            // EPERM) means TCC is blocking us: not granted.
            if err == ENOENT { continue }
        }
        return false
    }

    enum Choice {
        case proceed
        case openedSettings
    }

    /// Shows the explainer dialog when FDA is missing (at most once per
    /// launch, never if the user checked "Don't ask again").
    /// Returns `.openedSettings` when the user went to System Settings —
    /// callers should not start the scan in that case.
    static func promptIfNeeded() -> Choice {
        guard !askedThisLaunch,
              !UserDefaults.standard.bool(forKey: suppressKey),
              !isGranted
        else { return .proceed }
        askedThisLaunch = true

        let alert = NSAlert()
        alert.messageText = "Grant Full Disk Access?"
        alert.informativeText = """
        One grant in System Settings replaces the per-folder permission \
        popups and unlocks protected areas. Reopen MacDirStat afterward.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings…")
        alert.addButton(withTitle: "Scan Anyway")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressKey)
        }
        if response == .alertFirstButtonReturn {
            let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            NSWorkspace.shared.open(pane)
            return .openedSettings
        }
        return .proceed
    }
}
