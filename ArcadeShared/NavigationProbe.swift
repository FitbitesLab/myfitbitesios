#if DEBUG
import Foundation
/// Weak references observe the Too preview without retaining its scene.
@MainActor
enum NavigationProbe {
    static weak var too: StreetScene?
    static var tooTicks = 0
}
#endif
