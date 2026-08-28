import Foundation
import ServiceManagement

/// "Open at Login", via the modern `SMAppService` API.
///
/// Registering points macOS at *this bundle's current path*, so the app has to
/// be in its final home (`/Applications`) before it is registered — `install.sh`
/// copies first, then registers the copy. The registration shows up in System
/// Settings › General › Login Items, where the user can turn it off.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    static func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }

    static var statusDescription: String {
        switch status {
        case .enabled:
            return "enabled"
        case .notRegistered:
            return "not registered"
        case .requiresApproval:
            return "needs approval in System Settings › General › Login Items"
        case .notFound:
            return "not found (is the app in /Applications?)"
        @unknown default:
            return "unknown"
        }
    }
}

/// The `--…-login` flags `install.sh` uses. Running the executable inside the
/// bundle directly (rather than via `open`) lets the installer read the result.
enum LoginItemCommand: String {
    case status = "--login-status"
    case register = "--register-login"
    case unregister = "--unregister-login"

    static func parse(_ arguments: [String]) -> LoginItemCommand? {
        arguments.dropFirst().compactMap(LoginItemCommand.init(rawValue:)).first
    }

    /// Runs the command and returns the process exit code.
    func run() -> Int32 {
        do {
            switch self {
            case .status:
                break
            case .register:
                try LoginItem.enable()
            case .unregister:
                try LoginItem.disable()
            }
            print("Open at Login: \(LoginItem.statusDescription)")
            return 0
        } catch {
            FileHandle.standardError.write(
                Data("Open at Login failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
