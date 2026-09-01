import Foundation
import SwiftUI

struct CustomerDashboard: Identifiable {
    let id: Int
    let name: String
    let level: Int
    let xp: Int
    let xpToNext: Int
    let levelTarget: Int
    let memberSince: String
    let tierName: String
    let nextRewardMessage: String
    let currentStreakDays: Int
    let proteinThisWeek: Int
    let usualProduct: StoreProduct
    let hasOrderHistory: Bool
    let activeOrder: RightNowActiveOrder?
    let daysSinceLastCompletedOrder: Int?
    let completedOrderProductIDs: [String]
    let repeatedOrderCounts: [String: Int]
    let activeOrders: [CustomerOrderSummary]
    let pastOrders: [CustomerOrderSummary]
}

struct RewardsProgress {
    let level: Int
    let xp: Int
    let xpToNext: Int
    let levelTarget: Int
    let loyaltyStamps: Int
    let loyaltyTarget: Int
    let rewardsReady: Int
    let unannouncedFreeFitbitesRewardID: String?
    let freeFitbitesRewards: [FreeFitbitesReward]
    let freeFitbitesHistory: [FreeFitbitesReward]
    let freeFitbitesRedemptionEnabled: Bool
    let achievements: [Achievement]
    let ricoWallet: RicoWalletSummary
    let ricoStoreItems: [RicoStoreItem]
}

struct FreeFitbitesReward: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let issuedAt: String?
    let redeemedAt: String?
    let saleReference: String?
    let benefitDescription: String
}

struct FreeFitbitesRedemptionSession: Identifiable, Hashable {
    let id: String
    let status: String
    let expiresAt: String?
    let reservationExpiresAt: String?
    let qrToken: String?
    let fallbackCode: String?
    let reward: FreeFitbitesReward?
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let status: String
    let progress: Int?
    let target: Int?
    let xpReward: Int?
    let isUnlocked: Bool
    let tier: String?
    let category: String?
}

extension Array where Element == Achievement {
    var actionableAchievementQueue: [Achievement] {
        let indexed = enumerated().map { (offset: $0.offset, achievement: $0.element) }
        let locked = indexed.filter { !$0.achievement.isUnlocked }
        let unlocked = indexed.filter { $0.achievement.isUnlocked }
        var selectedOffsets = Set<Int>()
        var selected: [Achievement] = []

        if let nearestLevel = locked
            .filter({ $0.achievement.displayFamily == "level" })
            .sorted(by: achievementPriority)
            .first {
            selected.append(nearestLevel.achievement)
            selectedOffsets.insert(nearestLevel.offset)
        }

        let remainingFamilies = locked
            .filter { !selectedOffsets.contains($0.offset) }
            .sorted(by: achievementPriority)

        for item in remainingFamilies {
            guard !selected.contains(where: { $0.displayFamily == item.achievement.displayFamily }) else { continue }
            selected.append(item.achievement)
            selectedOffsets.insert(item.offset)
        }

        for item in remainingFamilies where !selectedOffsets.contains(item.offset) {
            selected.append(item.achievement)
            selectedOffsets.insert(item.offset)
        }

        selected.append(contentsOf: unlocked.map(\.achievement))

        return selected
    }

    var nextActionableAchievement: Achievement? {
        actionableAchievementQueue.first
    }

    private func achievementPriority(_ lhs: (offset: Int, achievement: Achievement), _ rhs: (offset: Int, achievement: Achievement)) -> Bool {
        let lhsRemaining = lhs.achievement.remainingProgress
        let rhsRemaining = rhs.achievement.remainingProgress

        if lhs.achievement.displayFamily == "level", rhs.achievement.displayFamily == "level", lhsRemaining != rhsRemaining {
            return lhsRemaining < rhsRemaining
        }

        if lhs.achievement.progressRatio != rhs.achievement.progressRatio {
            return lhs.achievement.progressRatio > rhs.achievement.progressRatio
        }

        return lhs.offset < rhs.offset
    }
}

private extension Achievement {
    var displayFamily: String {
        let categoryText = category?.lowercased() ?? ""
        let text = "\(categoryText) \(id) \(title) \(subtitle)".lowercased()

        if text.contains("level") {
            return "level"
        }
        if text.contains("coffee") || text.contains("cappuccin") {
            return "coffee"
        }
        if text.contains("order") {
            return "order"
        }
        if text.contains("streak") || text.contains("back") {
            return "habit"
        }
        if text.contains("lab") || text.contains("experiment") {
            return "lab"
        }
        if !categoryText.isEmpty {
            return categoryText
        }

        return id
    }

    var progressRatio: Double {
        guard let progress, let target, target > 0 else {
            return isUnlocked ? 1 : 0
        }

        return min(1, max(0, Double(progress) / Double(target)))
    }

    var remainingProgress: Int {
        guard let progress, let target else { return Int.max }
        return max(0, target - progress)
    }
}

struct RicoWalletSummary {
    let balance: Int
    let todayEarned: Int
    let dailyMax: Int
}

struct RicoStoreItem: Identifiable, Hashable {
    let id: String
    let name: String
    let shortDescription: String
    let flavorText: String
    let imageRef: String?
    let coinPrice: Int
    let itemType: String
    let remainingStock: Int?
    let isOwned: Bool
    let isAvailable: Bool
    let lockReason: String?
    let isLimited: Bool
}

struct TooLabProgress {
    struct DailyGame: Identifiable, Hashable {
        let gameIdentifier: String
        let claimed: Bool
        let xpAwarded: Int

        var id: String { gameIdentifier }
    }

    struct PrototypePurchase: Identifiable, Hashable {
        let id: String
        let prototypeIdentifier: String
        let xpAwarded: Int
        let feedbackXPAwarded: Int
        let feedbackSubmittedAt: String?
        let purchasedAt: String?
    }

    let totalLXP: Int
    let dailyGameXP: Int
    let prototypePurchaseXP: Int
    let prototypeFeedbackXP: Int
    let dailyGames: [DailyGame]
    let prototypePurchases: [PrototypePurchase]

    static let empty = TooLabProgress(
        totalLXP: 0,
        dailyGameXP: 25,
        prototypePurchaseXP: 250,
        prototypeFeedbackXP: 100,
        dailyGames: [],
        prototypePurchases: []
    )

    func hasClaimed(game identifier: String) -> Bool {
        dailyGames.first { $0.gameIdentifier == identifier }?.claimed ?? false
    }

    func purchase(for prototypeIdentifier: String) -> PrototypePurchase? {
        prototypePurchases.first { $0.prototypeIdentifier == prototypeIdentifier }
    }
}

struct CustomerOrderSummary: Identifiable, Hashable {
    struct LineItem: Identifiable, Hashable {
        let id: String
        let name: String
        let quantity: Int
        let total: String?
        let toppings: [String]
    }

    struct ReorderItem: Identifiable, Hashable {
        let productID: Int
        let quantity: Int
        let toppingIDs: [Int]

        var id: String {
            "\(productID)-\(toppingIDs.map(String.init).joined(separator: "-"))"
        }
    }

    let id: Int
    let status: String
    let statusLabel: String
    let statusCopy: String
    let time: String?
    let items: String
    let total: String
    let totalLabel: String
    let fulfillmentMethod: String?
    let deliveryAddress: String?
    let pickupScheduledAt: String?
    let paymentMethod: String?
    let lineItems: [LineItem]
    let reorderItems: [ReorderItem]
}

struct CustomerProfile {
    var name: String
    var phone: String
    var email: String
    var avatar: LocalAvatar
}

struct LocalAvatar: Hashable {
    var presetID: String
    var customPhotoData: Data?

    static let defaultPresetID = "too"

    static var `default`: LocalAvatar {
        LocalAvatar(presetID: defaultPresetID, customPhotoData: nil)
    }
}

struct LocalAvatarPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let imageName: String?
    let symbolName: String?
    let initials: String
    let colors: [Color]

    static let all: [LocalAvatarPreset] = [
        LocalAvatarPreset(
            id: "too",
            name: "Too",
            imageName: "AvatarToo",
            symbolName: nil,
            initials: "TOO",
            colors: [FBColors.cookieOrange, FBColors.tielYellow]
        ),
        LocalAvatarPreset(
            id: "tiel",
            name: "Tiel",
            imageName: "AvatarTiel",
            symbolName: nil,
            initials: "T",
            colors: [FBColors.tielYellow, Color(red: 1.0, green: 0.54, blue: 0.10)]
        ),
        LocalAvatarPreset(
            id: "rico",
            name: "Rico",
            imageName: "AvatarRico",
            symbolName: nil,
            initials: "R",
            colors: [Color(red: 0.18, green: 0.64, blue: 0.96), Color(red: 0.08, green: 0.22, blue: 0.62)]
        ),
        LocalAvatarPreset(
            id: "protein-toaster",
            name: "Protein Toaster",
            imageName: "AvatarProteinToaster",
            symbolName: nil,
            initials: "PT",
            colors: [Color(red: 0.98, green: 0.67, blue: 0.30), Color(red: 0.36, green: 0.24, blue: 0.14)]
        ),
        LocalAvatarPreset(
            id: "dev-presso",
            name: "Dev-Presso",
            imageName: "AvatarDevPresso",
            symbolName: nil,
            initials: "DP",
            colors: [Color(red: 0.16, green: 0.10, blue: 0.07), Color(red: 0.55, green: 0.34, blue: 0.18)]
        )
    ]

    static func preset(for id: String) -> LocalAvatarPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

struct CustomerAuthUser: Decodable, Equatable {
    let id: Int
    let name: String
    let phone: String?
    let email: String?
    let avatarUrl: String?
}

struct SavedAddress: Identifiable, Hashable, Codable {
    let id: String
    var label: String
    var detail: String
    var note: String
    var systemImage: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    var coordinateSource: DeliveryCoordinateSource? = nil
    var locationAccuracyM: Double? = nil
    var apartmentUnit: String? = nil
    var deliveryZoneID: Int? = nil
    var deliveryZoneName: String? = nil
    var lastQuotedDeliveryFeeVND: Int? = nil

    var isConfirmedForDelivery: Bool {
        latitude != nil && longitude != nil && coordinateSource != nil
    }
}

enum DeliveryCoordinateSource: String, Codable, Hashable {
    case appleMaps
    case deviceLocation

    var apiValue: String {
        switch self {
        case .appleMaps: "apple_maps"
        case .deviceLocation: "device_location"
        }
    }
}

struct StoreCatalog {
    let categories: [StoreCategory]
    let products: [StoreProduct]
    let featuredProductID: String
}

struct StoreCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let label: String
    let intro: String
    let imageName: String
    let markName: String
}

struct StoreProduct: Identifiable, Hashable {
    let id: String
    let inventoryItemID: Int
    let name: String
    let categoryID: String
    let description: String
    let ingredients: String
    let protein: String
    let calories: String
    let sugar: String
    let badge: String
    let priceVND: Int
    let imageName: String
    let imageURL: URL?
    let markName: String
    let isAvailable: Bool
    let pickupOnly: Bool
    let toppings: [StoreTopping]
}

enum TooLabClearance: Int, CaseIterable, Identifiable {
    case visitor = 0
    case labAssistant
    case authorizedTester
    case restrictedAccess
    case highSecurity
    case classified
    case omegaAccess
    case omegaClearance

    var id: Int { rawValue }

    var code: String {
        "C\(rawValue)"
    }

    var requiredLabXP: Int {
        switch self {
        case .visitor: 0
        case .labAssistant: 500
        case .authorizedTester: 2_000
        case .restrictedAccess: 3_500
        case .highSecurity: 5_000
        case .classified: 6_500
        case .omegaAccess: 8_000
        case .omegaClearance: 10_000
        }
    }

    var title: String {
        switch self {
        case .visitor: "VISITOR"
        case .labAssistant: "LAB ASSISTANT"
        case .authorizedTester: "AUTHORIZED TESTER"
        case .restrictedAccess: "RESTRICTED ACCESS"
        case .highSecurity: "HIGH SECURITY"
        case .classified: "CLASSIFIED"
        case .omegaAccess: "OMEGA ACCESS"
        case .omegaClearance: "OMEGA CLEARANCE"
        }
    }

    var subtitle: String {
        switch self {
        case .visitor: "C1 opens when the customer reaches Level 5."
        case .labAssistant: "Unlocks at 500 LXP."
        case .authorizedTester: "Unlocks at 2,000 LXP."
        case .restrictedAccess: "Unlocks at 3,500 LXP."
        case .highSecurity: "Unlocks at 5,000 LXP."
        case .classified: "Unlocks at 6,500 LXP."
        case .omegaAccess: "Unlocks at 8,000 LXP."
        case .omegaClearance: "Unlocks at 10,000 LXP."
        }
    }

    var color: Color {
        switch self {
        case .visitor: Color(red: 0.02, green: 0.76, blue: 0.12)
        case .labAssistant: Color(red: 0.04, green: 0.40, blue: 0.86)
        case .authorizedTester: Color(red: 1.00, green: 0.80, blue: 0.05)
        case .restrictedAccess: Color(red: 0.94, green: 0.48, blue: 0.00)
        case .highSecurity: Color(red: 0.90, green: 0.08, blue: 0.10)
        case .classified: Color(red: 0.65, green: 0.16, blue: 0.96)
        case .omegaAccess: Color(red: 0.18, green: 0.14, blue: 0.78)
        case .omegaClearance: Color(red: 0.03, green: 0.03, blue: 0.03)
        }
    }

    static func current(forLabXP labXP: Int) -> TooLabClearance {
        allCases.last { labXP >= $0.requiredLabXP } ?? .visitor
    }

    static func next(afterLabXP labXP: Int) -> TooLabClearance? {
        allCases.first { labXP < $0.requiredLabXP }
    }
}

struct StoreTopping: Identifiable, Hashable {
    let id: String
    let toppingID: Int
    let name: String
    let category: String
    let priceVND: Int
}

struct CartLine: Identifiable, Hashable {
    let id: UUID
    let product: StoreProduct
    let toppings: [StoreTopping]
    var quantity: Int

    var unitPriceVND: Int {
        product.priceVND + toppings.reduce(0) { $0 + $1.priceVND }
    }

    var totalVND: Int { unitPriceVND * quantity }

    var optionSummary: String {
        toppings.isEmpty ? "No toppings" : toppings.map(\.name).joined(separator: ", ")
    }
}
