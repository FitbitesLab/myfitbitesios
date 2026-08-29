import Foundation

enum RightNowCardState: Equatable, Identifiable {
    case activeOrder(RightNowActiveOrder)
    case labUnlock(RightNowLabUnlock)
    case rewardReady(RightNowRewardReady)
    case nearReward(RightNowNearReward)
    case welcomeBack(RightNowWelcomeBack)
    case usualOrder(RightNowUsualOrder)
    case streak(RightNowStreak)
    case discovery(RightNowDiscovery)
    case none

    var id: String {
        switch self {
        case .activeOrder:
            "active_order"
        case .labUnlock:
            "lab_unlock"
        case .rewardReady(let reward):
            reward.unannouncedRewardID.map { "reward_ready:\($0)" } ?? "reward_ready"
        case .nearReward:
            "near_reward"
        case .welcomeBack:
            "welcome_back"
        case .usualOrder:
            "usual_order"
        case .streak:
            "streak"
        case .discovery:
            "discovery"
        case .none:
            "none"
        }
    }
}

struct RightNowActiveOrder: Equatable {
    enum Status: Equatable {
        case preparing
        case ready
        case outForDelivery
    }

    let productName: String
    let orderNumber: String
    let status: Status
    let estimateText: String?
}

struct RightNowLabUnlock: Equatable {
    let id: String
    let level: Int
    let title: String
    let subtitle: String
}

struct RightNowRewardReady: Equatable {
    let availableCount: Int
    let unannouncedRewardID: String?

    var isNewUnlock: Bool {
        unannouncedRewardID != nil
    }
}

struct RightNowNearReward: Equatable {
    let stampsRemaining: Int
}

struct RightNowWelcomeBack: Equatable {
    let daysSinceLastOrder: Int
}

struct RightNowUsualOrder: Equatable {
    let product: StoreProduct
    let orderCount: Int
}

struct RightNowStreak: Equatable {
    let days: Int
}

struct RightNowDiscovery: Equatable {
    let product: StoreProduct
}

struct RightNowContext {
    let dashboard: CustomerDashboard
    let rewards: RewardsProgress
    let catalog: StoreCatalog
    let activeOrder: RightNowActiveOrder?
    let labUnlocks: [RightNowLabUnlock]
    let lastAcknowledgedLabUnlockID: String?
    let daysSinceLastCompletedOrder: Int?
    let completedOrderProductIDs: [String]
    let repeatedOrderCounts: [String: Int]
    let lastAcknowledgedStreakMilestone: Int
    let streakSurpriseDays: Int?
}

struct RightNowCardResolver {
    private let streakMilestones = [5]

    func resolve(context: RightNowContext) -> RightNowCardState {
        if let activeOrder = context.activeOrder {
            return .activeOrder(activeOrder)
        }

        if let unlock = unacknowledgedLabUnlock(in: context) {
            return .labUnlock(unlock)
        }

        if context.rewards.rewardsReady > 0 {
            return .rewardReady(
                RightNowRewardReady(
                    availableCount: context.rewards.rewardsReady,
                    unannouncedRewardID: context.rewards.unannouncedFreeFitbitesRewardID
                )
            )
        }

        let stampsRemaining = context.rewards.loyaltyTarget - context.rewards.loyaltyStamps
        if stampsRemaining == 1 {
            return .nearReward(RightNowNearReward(stampsRemaining: stampsRemaining))
        }

        if let streak = streakSurprise(in: context) {
            return .streak(streak)
        }

        if let daysSinceLastOrder = context.daysSinceLastCompletedOrder,
           daysSinceLastOrder >= 14,
           !context.completedOrderProductIDs.isEmpty {
            return .welcomeBack(RightNowWelcomeBack(daysSinceLastOrder: daysSinceLastOrder))
        }

        if let usual = usualOrder(in: context) {
            return .usualOrder(usual)
        }

        if let streak = milestoneStreak(in: context) {
            return .streak(streak)
        }

        if let discovery = discovery(in: context) {
            return .discovery(discovery)
        }

        return .none
    }

    private func unacknowledgedLabUnlock(in context: RightNowContext) -> RightNowLabUnlock? {
        context.labUnlocks
            .filter { $0.level <= context.dashboard.level }
            .filter { $0.id != context.lastAcknowledgedLabUnlockID }
            .sorted { $0.level > $1.level }
            .first
    }

    private func usualOrder(in context: RightNowContext) -> RightNowUsualOrder? {
        let repeated = context.repeatedOrderCounts
            .filter { $0.value >= 3 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }

        guard let candidate = repeated.first,
              let product = context.catalog.products.first(where: { product in
                  product.isAvailable && product.matchesOrderHistoryID(candidate.key)
              }) else {
            return nil
        }

        return RightNowUsualOrder(product: product, orderCount: candidate.value)
    }

    private func streakSurprise(in context: RightNowContext) -> RightNowStreak? {
        guard let days = context.streakSurpriseDays,
              days > 0,
              days <= context.dashboard.currentStreakDays else {
            return nil
        }

        return RightNowStreak(days: days)
    }

    private func milestoneStreak(in context: RightNowContext) -> RightNowStreak? {
        guard let milestone = streakMilestones.last(where: { $0 <= context.dashboard.currentStreakDays }),
              milestone > context.lastAcknowledgedStreakMilestone else {
            return nil
        }

        return RightNowStreak(days: milestone)
    }

    private func discovery(in context: RightNowContext) -> RightNowDiscovery? {
        guard let product = context.catalog.products.first(where: { product in
            product.isAvailable && !context.completedOrderProductIDs.contains(where: product.matchesOrderHistoryID)
        }) else {
            return nil
        }

        return RightNowDiscovery(product: product)
    }
}

private extension StoreProduct {
    func matchesOrderHistoryID(_ id: String) -> Bool {
        self.id == id || String(inventoryItemID) == id
    }
}

enum RightNowPersistenceKey {
    static let lastAcknowledgedLabUnlockID = "RightNowLastAcknowledgedLabUnlockID"
    static let lastAcknowledgedStreakMilestone = "RightNowLastAcknowledgedStreakMilestone"
    static let lastStreakSurpriseRollKey = "RightNowLastStreakSurpriseRollKey"
    static let debugOverride = "RightNowDebugOverride"
}

#if DEBUG
enum RightNowDebugOverride: String, CaseIterable, Identifiable {
    case automatic
    case activeOrder
    case labUnlock
    case rewardReady
    case nearReward
    case welcomeBack
    case usualOrder
    case streak
    case discovery
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .activeOrder:
            "Active Order"
        case .labUnlock:
            "Lab Unlock"
        case .rewardReady:
            "Reward Ready"
        case .nearReward:
            "Near Reward"
        case .welcomeBack:
            "Welcome Back"
        case .usualOrder:
            "Your Usual"
        case .streak:
            "Streak"
        case .discovery:
            "Discovery"
        case .none:
            "None"
        }
    }
}
#endif
