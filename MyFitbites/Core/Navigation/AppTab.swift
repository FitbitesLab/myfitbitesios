enum AppTab: Hashable {
    case home
    case order
    case progress
    case rewards
    case profile

    var title: String {
        switch self {
        case .home: "Home"
        case .order: "Order"
        case .progress: "Too's Lab"
        case .rewards: "Rewards"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .order: "bag"
        case .progress: "flask"
        case .rewards: "gift"
        case .profile: "person"
        }
    }
}
