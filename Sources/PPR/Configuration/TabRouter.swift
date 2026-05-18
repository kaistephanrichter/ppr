/// Shared tab-selection state injected into the environment,
/// so any child view can switch to a specific tab programmatically.
import Observation

@Observable
@MainActor
final class TabRouter {
    var selectedTab: Int = 0
}
