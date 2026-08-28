import Observation
import Foundation

/// Whether the notch is showing itself or hiding behind its tab.
///
/// Lives outside SwiftUI because the panel's hit-testing region has to follow
/// it: when collapsed, only the tab may claim mouse events.
@Observable
final class PanelState {
    private static let defaultsKey = "isExpanded"

    var isExpanded: Bool {
        didSet {
            guard isExpanded != oldValue else { return }
            if persists {
                UserDefaults.standard.set(isExpanded, forKey: Self.defaultsKey)
            }
            onChange?(isExpanded)
        }
    }

    /// Called whenever the state flips, so the panel can resize its hit region.
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    @ObservationIgnored private let persists: Bool

    init(expanded: Bool, persists: Bool = false) {
        self.isExpanded = expanded
        self.persists = persists
    }

    /// Restores the last state the user left the app in — collapsed the first time.
    static func restored() -> PanelState {
        PanelState(expanded: UserDefaults.standard.bool(forKey: defaultsKey), persists: true)
    }

    func toggle() {
        isExpanded.toggle()
    }
}
