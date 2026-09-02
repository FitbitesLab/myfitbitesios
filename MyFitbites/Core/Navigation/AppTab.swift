enum AppTab: Hashable {
    case home
    case order
    case progress
    case rewards

    var title: String {
        switch self {
        case .home: "Home"
        case .order: "Order"
        case .progress: "Too's Lab"
        case .rewards: "Rewards"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .order: "bag"
        case .progress: "flask"
        case .rewards: "gift"
        }
    }
}
