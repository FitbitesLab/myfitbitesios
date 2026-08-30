import Foundation
import Security
import UIKit

final class MyFitbitesMobileTokenStore {
    static let shared = MyFitbitesMobileTokenStore()

    private let service = "vn.com.fitbites.MyFitbites"
    private let account = "customer-mobile-token"

    private init() {}

    func token() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard
            status == errSecSuccess,
            let data = item as? Data,
            let token = String(data: data, encoding: .utf8),
            !token.isEmpty
        else {
            return nil
        }

        return token
    }

    func save(_ token: String?) {
        guard let token, !token.isEmpty, let data = token.data(using: .utf8) else {
            remove()
            return
        }

        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = baseQuery()
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func remove() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct LocalDashboardRepository: DashboardRepository {
    func dashboard() -> CustomerDashboard {
        CustomerDashboard(
            id: 1,
            name: "MyFitbites Member",
            level: 1,
            xp: 0,
            xpToNext: 500,
            levelTarget: 500,
            memberSince: "Preview",
            tierName: "Too's Apprentice",
            nextRewardMessage: "Your next reward is already taking shape.",
            currentStreakDays: 0,
            proteinThisWeek: 0,
            usualProduct: FixtureCatalog.products[0],
            hasOrderHistory: false,
            activeOrder: nil,
            daysSinceLastCompletedOrder: nil,
            completedOrderProductIDs: [],
            repeatedOrderCounts: [:],
            activeOrders: [],
            pastOrders: []
        )
    }
}

final class CustomerV2APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let mobileTokenStore: MyFitbitesMobileTokenStore
    private var cachedCSRFToken: String?

    init(
        baseURL: URL = CustomerV2APIClient.defaultBaseURL,
        session: URLSession = .shared,
        mobileTokenStore: MyFitbitesMobileTokenStore = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.mobileTokenStore = mobileTokenStore
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func dashboard() async throws -> CustomerV2DashboardPayload {
        try await get("/app-v2/data/dashboard")
    }

    func store() async throws -> CustomerV2StorePayload {
        try await get("/app-v2/data/store")
    }

    func sessionData() async throws -> CustomerV2SessionPayload {
        try await get("/app-v2/data/session")
    }

    func login(phone: String, password: String) async throws -> CustomerV2AuthPayload {
        let payload: CustomerV2AuthPayload = try await post("/app-v2/auth/login", body: [
            "phone": phone,
            "password": password
        ])
        mobileTokenStore.save(payload.mobileToken)
        return payload
    }

    func register(name: String, phone: String, email: String, password: String) async throws -> CustomerV2AuthPayload {
        var body = [
            "name": name,
            "phone": phone,
            "password": password
        ]

        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["email"] = email
        }

        let payload: CustomerV2AuthPayload = try await post("/app-v2/auth/register", body: body)
        mobileTokenStore.save(payload.mobileToken)
        return payload
    }

    func updateProfile(_ request: CustomerV2ProfileUpdateRequest) async throws -> CustomerV2AuthPayload {
        try await post("/app-v2/auth/profile", body: request)
    }

    func checkout(_ request: CustomerV2CheckoutRequest) async throws -> CustomerV2CheckoutPayload {
        try await post("/app-v2/checkout", body: request)
    }

    func deliveryQuote(_ request: CustomerV2DeliveryQuoteRequest) async throws -> CustomerV2DeliveryQuotePayload {
        try await post("/app-v2/delivery/quote", body: request)
    }

    func initiateVnpayPayment(_ request: CustomerV2VnpayInitiationRequest) async throws -> CustomerV2VnpayInitiationPayload {
        try await post("/app-v2/payments/vnpay/initiate", body: request)
    }

    func vnpayPaymentStatus(uuid: String, checkoutToken: String? = nil) async throws -> CustomerV2PaymentStatusPayload {
        try await get(
            "/app-v2/payments/vnpay/attempts/\(uuid)",
            queryItems: checkoutToken.map { [URLQueryItem(name: "checkout_token", value: $0)] } ?? []
        )
    }

    func rewardsSummary() async throws -> CustomerV2RewardsSummaryPayload {
        try await get("/app-v2/rewards/summary")
    }

    func rewardsIndex() async throws -> CustomerV2RewardsIndexPayload {
        try await get("/app-v2/rewards")
    }

    func acknowledgeFreeFitbitesAnnouncement(rewardID: String) async throws {
        let _: EmptyResponse = try await post("/app-v2/rewards/\(rewardID)/announcement-seen", body: EmptyRequestBody())
    }

    func createFreeFitbitesRedemptionSession(rewardID: String, idempotencyKey: String) async throws -> CustomerV2RewardRedemptionSessionEnvelope {
        try await post(
            "/app-v2/rewards/\(rewardID)/redemption-sessions",
            body: EmptyRequestBody(),
            headers: ["Idempotency-Key": idempotencyKey]
        )
    }

    func freeFitbitesRedemptionSession(id: String) async throws -> CustomerV2RewardRedemptionSessionEnvelope {
        try await get("/app-v2/reward-redemption-sessions/\(id)")
    }

    func cancelFreeFitbitesRedemptionSession(id: String) async throws {
        let _: EmptyResponse = try await delete("/app-v2/reward-redemption-sessions/\(id)")
    }

    func ricoStore() async throws -> CustomerV2RicoStorePayload {
        try await get("/app-v2/rico/store")
    }

    func purchaseRicoStoreItem(id: String, idempotencyKey: String) async throws -> CustomerV2RicoPurchasePayload {
        try await post(
            "/app-v2/rico/store/\(id)/purchase",
            body: EmptyRequestBody(),
            headers: ["Idempotency-Key": idempotencyKey]
        )
    }

    func ricoCollection() async throws -> CustomerV2RicoCollectionPayload {
        try await get("/app-v2/rico/collection")
    }

    func ricoPurchases() async throws -> CustomerV2RicoPurchasesPayload {
        try await get("/app-v2/rico/purchases")
    }

    func tooLabSummary() async throws -> CustomerV2TooLabEnvelope {
        try await get("/app-v2/too-lab")
    }

    func completeTooLabGame(identifier: String, score: Int = 0) async throws -> CustomerV2TooLabAwardPayload {
        try await post("/app-v2/too-lab/games/\(identifier)/complete", body: ["score": score])
    }

    func purchaseTooLabPrototype(identifier: String, idempotencyKey: String) async throws -> CustomerV2TooLabPrototypeAwardPayload {
        try await post(
            "/app-v2/too-lab/prototypes/\(identifier)/purchase",
            body: EmptyRequestBody(),
            headers: ["Idempotency-Key": idempotencyKey]
        )
    }

    func submitTooLabPrototypeFeedback(purchaseID: String, report: String) async throws -> CustomerV2TooLabPrototypeAwardPayload {
        try await post("/app-v2/too-lab/prototype-purchases/\(purchaseID)/feedback", body: ["report": report])
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let url = url(for: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyNativeHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, headers: [String: String] = [:]) async throws -> T {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await csrfToken(), forHTTPHeaderField: "X-CSRF-TOKEN")
        applyNativeHeaders(to: &request)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 419 {
            cachedCSRFToken = nil
            request.setValue(try await csrfToken(forceRefresh: true), forHTTPHeaderField: "X-CSRF-TOKEN")
            applyNativeHeaders(to: &request)
            let (retryData, retryResponse) = try await session.data(for: request)
            return try decodePostResponse(data: retryData, response: retryResponse)
        }

        return try decodePostResponse(data: data, response: response)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(try await csrfToken(), forHTTPHeaderField: "X-CSRF-TOKEN")
        applyNativeHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 419 {
            cachedCSRFToken = nil
            request.setValue(try await csrfToken(forceRefresh: true), forHTTPHeaderField: "X-CSRF-TOKEN")
            applyNativeHeaders(to: &request)
            let (retryData, retryResponse) = try await session.data(for: request)
            return try decodePostResponse(data: retryData, response: retryResponse)
        }

        return try decodePostResponse(data: data, response: response)
    }

    private func url(for path: String, queryItems: [URLQueryItem] = []) -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = cleanPath.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }

        guard !queryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.queryItems = queryItems
        return components.url ?? url
    }

    private func decodePostResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let errorPayload = try? decoder.decode(CustomerV2ValidationErrorPayload.self, from: data) {
                throw CustomerV2APIError.validation(
                    message: errorPayload.message ?? errorPayload.firstMessage ?? "Please check your details.",
                    fieldErrors: errorPayload.errors ?? [:]
                )
            }
            throw CustomerV2APIError.server("Fitbites could not complete that request.")
        }

        return try decoder.decode(T.self, from: data)
    }

    private func applyNativeHeaders(to request: inout URLRequest) {
        request.setValue("ios", forHTTPHeaderField: "X-MyFitbites-Client")
        request.setValue(UIDevice.current.name, forHTTPHeaderField: "X-MyFitbites-Device")

        if let token = mobileTokenStore.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func csrfToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let cachedCSRFToken {
            return cachedCSRFToken
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("app-v2"))
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        guard
            let html = String(data: data, encoding: .utf8),
            let range = html.range(of: #"<meta name="csrf-token" content=""#, options: .regularExpression)
        else {
            throw CustomerV2APIError.server("Fitbites could not prepare sign in.")
        }

        let tokenStart = range.upperBound
        guard let tokenEnd = html[tokenStart...].firstIndex(of: "\"") else {
            throw CustomerV2APIError.server("Fitbites could not prepare sign in.")
        }

        let token = String(html[tokenStart..<tokenEnd])
        cachedCSRFToken = token
        return token
    }

    private static var defaultBaseURL: URL {
        URL(string: "https://app.fitbites.com.vn")!
    }
}

@MainActor
final class APIBackedDashboardRepository: DashboardRepository, CustomerDataRefreshing, CustomerV2DashboardPayloadCaching, CustomerV2AuthenticatedUserCaching {
    private let client: CustomerV2APIClient
    private let fallback: DashboardRepository
    private var cachedDashboard: CustomerDashboard

    init(client: CustomerV2APIClient, fallback: DashboardRepository) {
        self.client = client
        self.fallback = fallback
        self.cachedDashboard = fallback.dashboard()
    }

    func dashboard() -> CustomerDashboard {
        cachedDashboard
    }

    func refresh() async {
        guard let payload = try? await client.dashboard() else { return }
        applyDashboardPayload(payload)
    }

    func applyDashboardPayload(_ payload: CustomerV2DashboardPayload) {
        cachedDashboard = CustomerV2Mapper.dashboard(from: payload, fallback: fallback.dashboard())
    }

    func applyAuthenticatedUser(_ user: CustomerAuthUser) {
        cachedDashboard = CustomerDashboard(
            id: user.id,
            name: user.name,
            level: cachedDashboard.level,
            xp: cachedDashboard.xp,
            xpToNext: cachedDashboard.xpToNext,
            levelTarget: cachedDashboard.levelTarget,
            memberSince: cachedDashboard.memberSince,
            tierName: cachedDashboard.tierName,
            nextRewardMessage: cachedDashboard.nextRewardMessage,
            currentStreakDays: cachedDashboard.currentStreakDays,
            proteinThisWeek: cachedDashboard.proteinThisWeek,
            usualProduct: cachedDashboard.usualProduct,
            hasOrderHistory: cachedDashboard.hasOrderHistory,
            activeOrder: cachedDashboard.activeOrder,
            daysSinceLastCompletedOrder: cachedDashboard.daysSinceLastCompletedOrder,
            completedOrderProductIDs: cachedDashboard.completedOrderProductIDs,
            repeatedOrderCounts: cachedDashboard.repeatedOrderCounts,
            activeOrders: cachedDashboard.activeOrders,
            pastOrders: cachedDashboard.pastOrders
        )
    }
}

@MainActor
final class APIBackedCatalogRepository: CatalogRepository, CustomerDataRefreshing {
    private let client: CustomerV2APIClient
    private let fallback: CatalogRepository
    private var cachedCatalog: StoreCatalog

    init(client: CustomerV2APIClient, fallback: CatalogRepository) {
        self.client = client
        self.fallback = fallback
        self.cachedCatalog = fallback.catalog()
    }

    func catalog() -> StoreCatalog {
        cachedCatalog
    }

    func refresh() async {
        guard
            let payload = try? await client.store(),
            let catalog = CustomerV2Mapper.catalog(from: payload, fallback: fallback.catalog())
        else { return }

        cachedCatalog = catalog
    }
}

@MainActor
final class APIBackedRewardsRepository: RewardsRepository, CustomerDataRefreshing, CustomerV2DashboardPayloadCaching {
    private let client: CustomerV2APIClient
    private let fallback: RewardsRepository
    private var cachedRewards: RewardsProgress

    init(client: CustomerV2APIClient, fallback: RewardsRepository) {
        self.client = client
        self.fallback = fallback
        self.cachedRewards = fallback.rewards()
    }

    func rewards() -> RewardsProgress {
        cachedRewards
    }

    func refresh() async {
        if let payload = try? await client.dashboard() {
            applyDashboardPayload(payload)
        }

        guard let summary = try? await client.rewardsSummary() else { return }
        let store = try? await client.ricoStore()
        let rewardIndex = try? await client.rewardsIndex()
        cachedRewards = CustomerV2Mapper.rewards(from: summary, store: store, rewardIndex: rewardIndex, fallback: cachedRewards)
    }

    func applyDashboardPayload(_ payload: CustomerV2DashboardPayload) {
        cachedRewards = CustomerV2Mapper.rewards(from: payload, fallback: cachedRewards)
    }
}

struct CustomerV2DashboardPayload: Decodable {
    let member: Member?
    let loyalty: Loyalty?
    let achievements: [AchievementPayload]?
    let stats: [Stat]?
    let orders: Orders?

    struct Member: Decodable {
        let id: Int?
        let name: String?
        let tier: String?
        let level: Int?
        let xp: Int?
        let levelXp: Int?
        let levelTarget: Int?
        let xpToNext: Int?
        let joinedAt: String?
    }

    struct Loyalty: Decodable {
        let stamps: Int?
        let target: Int?
        let rewards: Int?
        let message: String?
        let unannouncedReward: UnannouncedReward?

        struct UnannouncedReward: Decodable {
            let id: String?
            let type: String?
            let name: String?
            let status: String?
            let issuedAt: String?
            let benefit: CustomerV2RewardsIndexPayload.Benefit?
        }
    }

    struct AchievementPayload: Decodable {
        let id: FlexibleString?
        let name: String?
        let description: String?
        let status: String?
        let category: String?
        let tier: String?
        let tierIcon: String?
        let xpReward: Int?
        let xp: Int?
        let progress: Int?
        let target: Int?
        let isUnlocked: Bool?
    }

    struct Stat: Decodable {
        let label: String?
        let value: FlexibleString?
        let icon: String?
    }

    struct Orders: Decodable {
        let active: Int?
        let activeItems: [OrderSummary]?
        let pastItems: [OrderSummary]?
    }

    struct OrderSummary: Decodable {
        let id: Int?
        let status: String?
        let statusLabel: String?
        let statusCopy: String?
        let time: String?
        let sortTime: Int?
        let items: String?
        let total: FlexibleString?
        let totalLabel: String?
        let lineItems: [LineItem]?
        let reorderItems: [ReorderItem]?
        let fulfillmentMethod: String?
        let deliveryAddress: String?
        let pickupScheduledAt: String?
        let paymentMethod: String?
    }

    struct LineItem: Decodable {
        let name: String?
        let quantity: Int?
        let total: FlexibleString?
        let toppings: [Topping]?
    }

    struct Topping: Decodable {
        let name: String?
        let quantity: Int?
    }

    struct ReorderItem: Decodable {
        let productId: Int?
        let inventoryItemId: Int?
        let quantity: Int?
        let toppingIds: [Int]?
    }
}

struct CustomerV2SessionPayload: Decodable {
    let authenticated: Bool
    let user: CustomerAuthUser?
}

struct CustomerV2AuthPayload: Decodable {
    let success: Bool?
    let user: CustomerAuthUser?
    let mobileToken: String?
}

struct CustomerV2ProfileUpdateRequest: Encodable {
    let name: String
    let phone: String
    let email: String?
    let currentPassword: String?
    let password: String?
    let passwordConfirmation: String?
}

struct EmptyRequestBody: Encodable {}

struct EmptyResponse: Decodable {}

struct CustomerV2ValidationErrorPayload: Decodable {
    let message: String?
    let errors: [String: [String]]?
    let error: CustomerV2MachineErrorPayload?

    var firstMessage: String? {
        error?.message ?? errors?.values.first?.first
    }
}

struct CustomerV2MachineErrorPayload: Decodable {
    let code: String?
    let message: String?
}

struct CustomerV2CheckoutRequest: Encodable {
    let cart: [Item]
    let checkoutToken: String
    let fulfillmentMethod: String
    let paymentMethod: String
    let customerNotes: String?
    let coordinateSource: String?
    let deliveryZoneId: Int?
    let recipientName: String?
    let deliveryPhone: String?
    let deliveryAddress: String?
    let deliveryNotes: String?
    let deliveryLatitude: Double?
    let deliveryLongitude: Double?
    let deliveryLocationAccuracyM: Double?

    struct Item: Encodable {
        let id: Int
        let quantity: Int
        let toppings: [Topping]
        let customerNotes: String?
    }

    struct Topping: Encodable {
        let id: Int
    }
}

struct CustomerV2CheckoutPayload: Decodable {
    let success: Bool
    let order: Order

    struct Order: Decodable {
        let id: Int
        let url: String?
        let total: FlexibleInt
        let subtotal: FlexibleInt
        let deliveryFee: FlexibleInt
        let fulfillmentMethod: String
        let pickupScheduledAt: String?
        let paymentMethod: String
        let paymentReference: String?
        let paymentQrImage: String?
    }
}

struct CustomerV2VnpayInitiationRequest: Encodable {
    let pendingOrderId: Int
    let checkoutToken: String?
    let bankCode: String?
}

struct CustomerV2VnpayInitiationPayload: Decodable {
    let paymentAttempt: PaymentAttempt
    let paymentUrl: URL

    struct PaymentAttempt: Decodable {
        let uuid: String
        let provider: String
        let paymentMethod: String
        let amount: FlexibleInt
        let currency: String
        let status: String
    }
}

struct CustomerV2PaymentStatusPayload: Decodable {
    let paymentAttempt: PaymentAttempt
    let pendingOrder: PendingOrder

    struct PaymentAttempt: Decodable {
        let uuid: String
        let provider: String
        let paymentMethod: String
        let amount: FlexibleInt
        let currency: String
        let status: String
        let providerTransactionReference: String?
    }

    struct PendingOrder: Decodable {
        let id: Int
        let paymentMethod: String
        let paymentStatus: String
        let paymentReference: String?
        let paidAt: String?
        let total: FlexibleInt
    }
}

struct CustomerV2DeliveryQuoteRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let coordinateSource: String
}

struct CustomerV2DeliveryQuotePayload: Decodable {
    let deliverable: Bool
    let deliveryZoneId: Int?
    let zoneName: String?
    let deliveryFee: FlexibleInt?
}

struct CustomerV2RewardsSummaryPayload: Decodable {
    let wallet: Wallet?
    let loyalty: Loyalty?
    let achievements: AchievementSummary?

    struct Wallet: Decodable {
        let balance: Int?
        let todayEarned: Int?
        let dailyMax: Int?
    }

    struct Loyalty: Decodable {
        let stamps: Int?
        let target: Int?
        let rewards: Int?
        let nextReward: String?
    }

    struct AchievementSummary: Decodable {
        let total: Int?
        let unlocked: Int?
    }
}

struct CustomerV2RewardsIndexPayload: Decodable {
    let rewards: Rewards?

    struct Rewards: Decodable {
        let available: [Reward]?
        let history: [Reward]?
        let availableCount: Int?
        let redemptionEnabled: Bool?
        let policy: Benefit?
    }
}

struct CustomerV2RewardRedemptionSessionEnvelope: Decodable {
    let redemptionSession: Session?

    struct Session: Decodable {
        let id: String?
        let status: String?
        let expiresAt: String?
        let reservationExpiresAt: String?
        let qrToken: String?
        let fallbackCode: String?
        let reward: CustomerV2RewardsIndexPayload.Reward?
    }
}

extension CustomerV2RewardsIndexPayload {
    struct Reward: Decodable {
        let id: String?
        let type: String?
        let name: String?
        let status: String?
        let issuedAt: String?
        let redeemedAt: String?
        let saleReference: String?
        let benefit: Benefit?
    }

    struct Benefit: Decodable {
        let description: String?
    }
}

struct CustomerV2RicoStorePayload: Decodable {
    let items: [Item]?

    struct Item: Decodable {
        let id: String?
        let name: String?
        let shortDescription: String?
        let flavorText: String?
        let imageRef: String?
        let coinPrice: Int?
        let itemType: String?
        let remainingStock: Int?
        let perCustomerLimit: Int?
        let isOwned: Bool?
        let isAvailable: Bool?
        let lockReason: String?
    }
}

struct CustomerV2RicoPurchasePayload: Decodable {
    let purchase: Purchase?
    let wallet: CustomerV2RewardsSummaryPayload.Wallet?

    struct Purchase: Decodable {
        let id: Int?
        let itemId: String?
        let itemName: String?
        let coinPrice: Int?
        let status: String?
        let grant: Grant?
        let claim: Claim?
    }

    struct Grant: Decodable {
        let type: String?
        let entitlementType: String?
    }

    struct Claim: Decodable {
        let type: String?
        let status: String?
        let pickupDeadlineAt: String?
    }
}

struct CustomerV2RicoCollectionPayload: Decodable {
    let items: [Item]?

    struct Item: Decodable {
        let id: Int?
        let itemId: String?
        let name: String?
        let itemType: String?
        let imageRef: String?
        let acquiredAt: String?
    }
}

struct CustomerV2RicoPurchasesPayload: Decodable {
    let purchases: [CustomerV2RicoPurchasePayload.Purchase]?
}

struct CustomerV2TooLabEnvelope: Decodable {
    let tooLab: CustomerV2TooLabPayload?
}

struct CustomerV2TooLabAwardPayload: Decodable {
    let awardedLxp: Int?
    let alreadyClaimed: Bool?
    let summary: CustomerV2TooLabPayload?
}

struct CustomerV2TooLabPrototypeAwardPayload: Decodable {
    let purchase: CustomerV2TooLabPayload.PrototypePurchase?
    let awardedLxp: Int?
    let alreadyPurchased: Bool?
    let alreadySubmitted: Bool?
    let summary: CustomerV2TooLabPayload?
}

struct CustomerV2TooLabPayload: Decodable {
    let totalLxp: Int?
    let dailyGameXp: Int?
    let prototypePurchaseXp: Int?
    let prototypeFeedbackXp: Int?
    let dailyGames: [DailyGame]?
    let prototypePurchases: [PrototypePurchase]?

    struct DailyGame: Decodable {
        let gameIdentifier: String?
        let claimed: Bool?
        let xpAwarded: Int?
    }

    struct PrototypePurchase: Decodable {
        let id: String?
        let prototypeIdentifier: String?
        let xpAwarded: Int?
        let feedbackXpAwarded: Int?
        let feedbackSubmittedAt: String?
        let purchasedAt: String?
    }
}

enum CustomerV2APIError: LocalizedError {
    case validation(message: String, fieldErrors: [String: [String]])
    case server(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message, _), .server(let message):
            message
        }
    }
}

struct CustomerV2StorePayload: Decodable {
    let chapters: [Chapter]?

    struct Chapter: Decodable {
        let name: String?
        let intro: String?
        let products: [Product]?
    }

    struct Product: Decodable {
        let id: Int?
        let checkoutId: Int?
        let inventoryItemId: Int?
        let name: String?
        let displayName: String?
        let editorialTitle: String?
        let editorialSubtitle: String?
        let description: String?
        let macroLine: String?
        let macro: String?
        let image: String?
        let thumbnailImage: String?
        let priceValue: FlexibleInt?
        let isAvailable: Bool?
        let isOrderable: Bool?
        let pickupOnly: Bool?
        let toppings: [Topping]?
    }

    struct Topping: Decodable {
        let id: Int?
        let checkoutId: Int?
        let name: String?
        let category: String?
        let posCategory: String?
        let priceValue: FlexibleInt?
    }
}

struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = double.formatted()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : "false"
        } else {
            value = ""
        }
    }
}

struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(double.rounded())
        } else if let string = try? container.decode(String.self), let double = Double(string) {
            value = Int(double.rounded())
        } else {
            value = 0
        }
    }
}

enum CustomerV2Mapper {
    static func dashboard(from payload: CustomerV2DashboardPayload, fallback: CustomerDashboard) -> CustomerDashboard {
        let member = payload.member
        let loyalty = payload.loyalty
        let completedProductIDs = completedOrderProductIDs(from: payload)

        return CustomerDashboard(
            id: member?.id ?? fallback.id,
            name: member?.name ?? fallback.name,
            level: member?.level ?? fallback.level,
            xp: member?.xp ?? fallback.xp,
            xpToNext: member?.xpToNext ?? fallback.xpToNext,
            levelTarget: member?.levelTarget ?? fallback.levelTarget,
            memberSince: joinedDateLabel(from: member?.joinedAt) ?? fallback.memberSince,
            tierName: member?.tier ?? fallback.tierName,
            nextRewardMessage: loyalty?.message ?? fallback.nextRewardMessage,
            currentStreakDays: streakDays(from: statValue("Current streak", in: payload.stats)) ?? 0,
            proteinThisWeek: fallback.proteinThisWeek,
            usualProduct: fallback.usualProduct,
            hasOrderHistory: orderCount(from: payload.stats) > 0,
            activeOrder: activeOrder(from: payload),
            daysSinceLastCompletedOrder: daysSinceLastCompletedOrder(from: payload),
            completedOrderProductIDs: completedProductIDs,
            repeatedOrderCounts: repeatedOrderCounts(from: completedProductIDs),
            activeOrders: orderSummaries(from: payload.orders?.activeItems),
            pastOrders: orderSummaries(from: payload.orders?.pastItems)
        )
    }

    static func rewards(from payload: CustomerV2DashboardPayload, fallback: RewardsProgress) -> RewardsProgress {
        let member = payload.member
        let loyalty = payload.loyalty
        let achievements = payload.achievements?.compactMap(achievement(from:)) ?? []

        return RewardsProgress(
            level: member?.level ?? fallback.level,
            xp: member?.xp ?? fallback.xp,
            xpToNext: member?.xpToNext ?? fallback.xpToNext,
            levelTarget: member?.levelTarget ?? fallback.levelTarget,
            loyaltyStamps: loyalty?.stamps ?? fallback.loyaltyStamps,
            loyaltyTarget: loyalty?.target ?? fallback.loyaltyTarget,
            rewardsReady: loyalty?.rewards ?? fallback.rewardsReady,
            unannouncedFreeFitbitesRewardID: loyalty?.unannouncedReward?.id ?? fallback.unannouncedFreeFitbitesRewardID,
            freeFitbitesRewards: fallback.freeFitbitesRewards,
            freeFitbitesHistory: fallback.freeFitbitesHistory,
            freeFitbitesRedemptionEnabled: fallback.freeFitbitesRedemptionEnabled,
            achievements: achievements.isEmpty ? fallback.achievements : achievements,
            ricoWallet: fallback.ricoWallet,
            ricoStoreItems: fallback.ricoStoreItems
        )
    }

    static func rewards(from summary: CustomerV2RewardsSummaryPayload, store: CustomerV2RicoStorePayload?, rewardIndex: CustomerV2RewardsIndexPayload?, fallback: RewardsProgress) -> RewardsProgress {
        let wallet = summary.wallet
        let loyalty = summary.loyalty
        let freeRewards = rewardIndex?.rewards?.available?.compactMap(freeFitbitesReward(from:)) ?? fallback.freeFitbitesRewards
        let history = rewardIndex?.rewards?.history?.compactMap(freeFitbitesReward(from:)) ?? fallback.freeFitbitesHistory

        return RewardsProgress(
            level: fallback.level,
            xp: fallback.xp,
            xpToNext: fallback.xpToNext,
            levelTarget: fallback.levelTarget,
            loyaltyStamps: loyalty?.stamps ?? fallback.loyaltyStamps,
            loyaltyTarget: loyalty?.target ?? fallback.loyaltyTarget,
            rewardsReady: rewardIndex?.rewards?.availableCount ?? loyalty?.rewards ?? fallback.rewardsReady,
            unannouncedFreeFitbitesRewardID: fallback.unannouncedFreeFitbitesRewardID,
            freeFitbitesRewards: freeRewards,
            freeFitbitesHistory: history,
            freeFitbitesRedemptionEnabled: rewardIndex?.rewards?.redemptionEnabled ?? fallback.freeFitbitesRedemptionEnabled,
            achievements: fallback.achievements,
            ricoWallet: RicoWalletSummary(
                balance: wallet?.balance ?? fallback.ricoWallet.balance,
                todayEarned: wallet?.todayEarned ?? fallback.ricoWallet.todayEarned,
                dailyMax: wallet?.dailyMax ?? fallback.ricoWallet.dailyMax
            ),
            ricoStoreItems: (store?.items ?? []).compactMap(ricoStoreItem(from:))
        )
    }

    static func redemptionSession(from envelope: CustomerV2RewardRedemptionSessionEnvelope) -> FreeFitbitesRedemptionSession? {
        guard let session = envelope.redemptionSession, let id = session.id else { return nil }

        return FreeFitbitesRedemptionSession(
            id: id,
            status: session.status ?? "pending",
            expiresAt: session.expiresAt,
            reservationExpiresAt: session.reservationExpiresAt,
            qrToken: session.qrToken,
            fallbackCode: session.fallbackCode,
            reward: session.reward.flatMap(freeFitbitesReward(from:))
        )
    }

    static func tooLabProgress(from payload: CustomerV2TooLabPayload?, fallback: TooLabProgress = .empty) -> TooLabProgress {
        guard let payload else { return fallback }

        return TooLabProgress(
            totalLXP: payload.totalLxp ?? fallback.totalLXP,
            dailyGameXP: payload.dailyGameXp ?? fallback.dailyGameXP,
            prototypePurchaseXP: payload.prototypePurchaseXp ?? fallback.prototypePurchaseXP,
            prototypeFeedbackXP: payload.prototypeFeedbackXp ?? fallback.prototypeFeedbackXP,
            dailyGames: (payload.dailyGames ?? []).compactMap { game in
                guard let identifier = nonEmpty(game.gameIdentifier) else { return nil }
                return TooLabProgress.DailyGame(
                    gameIdentifier: identifier,
                    claimed: game.claimed ?? false,
                    xpAwarded: game.xpAwarded ?? 0
                )
            },
            prototypePurchases: (payload.prototypePurchases ?? []).compactMap { purchase in
                guard let id = nonEmpty(purchase.id),
                      let prototypeIdentifier = nonEmpty(purchase.prototypeIdentifier)
                else { return nil }

                return TooLabProgress.PrototypePurchase(
                    id: id,
                    prototypeIdentifier: prototypeIdentifier,
                    xpAwarded: purchase.xpAwarded ?? 0,
                    feedbackXPAwarded: purchase.feedbackXpAwarded ?? 0,
                    feedbackSubmittedAt: purchase.feedbackSubmittedAt,
                    purchasedAt: purchase.purchasedAt
                )
            }
        )
    }

    private static func freeFitbitesReward(from payload: CustomerV2RewardsIndexPayload.Reward) -> FreeFitbitesReward? {
        guard let id = payload.id else { return nil }

        return FreeFitbitesReward(
            id: id,
            name: payload.name ?? "Free Reward",
            status: payload.status ?? "available",
            issuedAt: payload.issuedAt,
            redeemedAt: payload.redeemedAt,
            saleReference: payload.saleReference,
            benefitDescription: payload.benefit?.description ?? "Choose one Daily Go, Daily Classic, or standard coffee at the counter."
        )
    }

    static func catalog(from payload: CustomerV2StorePayload, fallback: StoreCatalog) -> StoreCatalog? {
        guard let chapters = payload.chapters, !chapters.isEmpty else { return nil }

        let categories = chapters.map { chapter -> StoreCategory in
            let name = nonEmpty(chapter.name) ?? "Fitbites"
            let imagePair = categoryImages(for: name)
            return StoreCategory(
                id: slug(name),
                name: name,
                label: name.uppercased(),
                intro: nonEmpty(chapter.intro) ?? "Fresh Fitbites picks.",
                imageName: imagePair.image,
                markName: imagePair.mark
            )
        }

        let products = zip(chapters, categories).flatMap { chapter, category -> [StoreProduct] in
            return (chapter.products ?? []).compactMap { product in
                storeProduct(from: product, category: category)
            }
        }

        guard !products.isEmpty else { return nil }

        return StoreCatalog(
            categories: categories,
            products: products,
            featuredProductID: products.first?.id ?? fallback.featuredProductID
        )
    }

    private static func storeProduct(from product: CustomerV2StorePayload.Product, category: StoreCategory) -> StoreProduct? {
        guard
            let sourceID = product.id,
            let name = nonEmpty(product.displayName) ?? nonEmpty(product.name),
            let inventoryID = product.checkoutId ?? product.inventoryItemId ?? product.id
        else { return nil }

        let toppings = (product.toppings ?? []).compactMap(storeTopping(from:))
        let macro = nonEmpty(product.macroLine) ?? nonEmpty(product.macro) ?? "Nutrition unavailable"
        let nutrition = nutritionValues(from: macro)

        return StoreProduct(
            id: "api-\(sourceID)",
            inventoryItemID: inventoryID,
            name: name,
            categoryID: category.id,
            description: nonEmpty(product.description) ?? nonEmpty(product.editorialSubtitle) ?? "Fresh from the Fitbites kitchen.",
            ingredients: macro,
            protein: nutrition.protein,
            calories: nutrition.calories,
            sugar: nutrition.sugar,
            badge: nonEmpty(product.editorialTitle) ?? category.name,
            priceVND: product.priceValue?.value ?? 0,
            imageName: localImageName(for: name, category: category),
            imageURL: webURL(from: nonEmpty(product.image) ?? nonEmpty(product.thumbnailImage)),
            markName: category.markName,
            isAvailable: product.isAvailable ?? product.isOrderable ?? true,
            pickupOnly: product.pickupOnly ?? false,
            toppings: toppings
        )
    }

    private static func storeTopping(from topping: CustomerV2StorePayload.Topping) -> StoreTopping? {
        guard
            let sourceID = topping.id,
            let checkoutID = topping.checkoutId ?? topping.id,
            let name = nonEmpty(topping.name)
        else { return nil }

        return StoreTopping(
            id: "api-topping-\(sourceID)",
            toppingID: checkoutID,
            name: name,
            category: nonEmpty(topping.category) ?? nonEmpty(topping.posCategory) ?? "Extras",
            priceVND: topping.priceValue?.value ?? 0
        )
    }

    private static func achievement(from payload: CustomerV2DashboardPayload.AchievementPayload) -> Achievement? {
        guard let id = nonEmpty(payload.id?.value), let title = nonEmpty(payload.name) else { return nil }

        return Achievement(
            id: id,
            title: title,
            subtitle: nonEmpty(payload.description) ?? nonEmpty(payload.status) ?? "Unlocked",
            systemImage: nonEmpty(payload.tierIcon) ?? "star.fill",
            status: nonEmpty(payload.status) ?? "In progress",
            progress: payload.progress,
            target: payload.target,
            xpReward: payload.xpReward ?? payload.xp,
            isUnlocked: payload.isUnlocked ?? (payload.status?.lowercased() == "unlocked"),
            tier: nonEmpty(payload.tier)
        )
    }

    private static func ricoStoreItem(from payload: CustomerV2RicoStorePayload.Item) -> RicoStoreItem? {
        guard
            let id = nonEmpty(payload.id),
            let name = nonEmpty(payload.name)
        else { return nil }

        return RicoStoreItem(
            id: id,
            name: name,
            shortDescription: nonEmpty(payload.shortDescription) ?? "Rico Store item",
            flavorText: nonEmpty(payload.flavorText) ?? "",
            imageRef: nonEmpty(payload.imageRef),
            coinPrice: payload.coinPrice ?? 0,
            itemType: nonEmpty(payload.itemType) ?? "digital_collectible",
            remainingStock: payload.remainingStock,
            isOwned: payload.isOwned ?? false,
            isAvailable: payload.isAvailable ?? false,
            lockReason: nonEmpty(payload.lockReason),
            isLimited: payload.remainingStock != nil || payload.perCustomerLimit != nil
        )
    }

    private static func orderSummaries(from payloads: [CustomerV2DashboardPayload.OrderSummary]?) -> [CustomerOrderSummary] {
        (payloads ?? []).compactMap(orderSummary(from:))
    }

    private static func orderSummary(from payload: CustomerV2DashboardPayload.OrderSummary) -> CustomerOrderSummary? {
        guard let id = payload.id else { return nil }

        return CustomerOrderSummary(
            id: id,
            status: nonEmpty(payload.status) ?? "pending",
            statusLabel: nonEmpty(payload.statusLabel) ?? "Pending",
            statusCopy: nonEmpty(payload.statusCopy) ?? "Fitbites is checking your order.",
            time: nonEmpty(payload.time),
            items: nonEmpty(payload.items) ?? "Fitbites order",
            total: nonEmpty(payload.total?.value) ?? "",
            totalLabel: nonEmpty(payload.totalLabel) ?? "Total",
            fulfillmentMethod: nonEmpty(payload.fulfillmentMethod),
            deliveryAddress: nonEmpty(payload.deliveryAddress),
            pickupScheduledAt: nonEmpty(payload.pickupScheduledAt),
            paymentMethod: nonEmpty(payload.paymentMethod),
            lineItems: (payload.lineItems ?? []).enumerated().compactMap { index, line in
                guard let name = nonEmpty(line.name) else { return nil }
                return CustomerOrderSummary.LineItem(
                    id: "\(id)-\(index)",
                    name: name,
                    quantity: max(1, line.quantity ?? 1),
                    total: nonEmpty(line.total?.value),
                    toppings: (line.toppings ?? []).compactMap { topping in
                        guard let name = nonEmpty(topping.name) else { return nil }
                        let quantity = max(1, topping.quantity ?? 1)
                        return quantity > 1 ? "\(quantity)x \(name)" : name
                    }
                )
            },
            reorderItems: (payload.reorderItems ?? []).compactMap { item in
                guard let productID = item.inventoryItemId ?? item.productId else { return nil }
                return CustomerOrderSummary.ReorderItem(
                    productID: productID,
                    quantity: max(1, item.quantity ?? 1),
                    toppingIDs: item.toppingIds ?? []
                )
            }
        )
    }

    private static func activeOrder(from payload: CustomerV2DashboardPayload) -> RightNowActiveOrder? {
        guard let order = payload.orders?.activeItems?.first else { return nil }

        let status = order.status?.lowercased()
        let mappedStatus: RightNowActiveOrder.Status
        switch status {
        case "ready":
            mappedStatus = .ready
        case "out_for_delivery", "out-for-delivery", "delivery", "delivering":
            mappedStatus = .outForDelivery
        case "submitted", "accepted", "pending", "preparing":
            mappedStatus = .preparing
        default:
            mappedStatus = .preparing
        }

        let productName = order.lineItems?.compactMap { nonEmpty($0.name) }.first
            ?? nonEmpty(order.items)
            ?? "Your Fitbites"
        let orderNumber = order.id.map { "#\($0)" } ?? "#--"
        let estimateText = nonEmpty(order.statusLabel)

        return RightNowActiveOrder(
            productName: productName,
            orderNumber: orderNumber,
            status: mappedStatus,
            estimateText: estimateText
        )
    }

    private static func completedOrderProductIDs(from payload: CustomerV2DashboardPayload) -> [String] {
        (payload.orders?.pastItems ?? [])
            .filter { $0.status?.lowercased() == "completed" }
            .flatMap { order in
                (order.reorderItems ?? []).flatMap { item -> [String] in
                    let quantity = max(1, item.quantity ?? 1)
                    guard let inventoryID = item.inventoryItemId ?? item.productId else { return [] }
                    return Array(repeating: "\(inventoryID)", count: quantity)
                }
            }
    }

    private static func repeatedOrderCounts(from productIDs: [String]) -> [String: Int] {
        productIDs.reduce(into: [:]) { counts, productID in
            counts[productID, default: 0] += 1
        }
    }

    private static func daysSinceLastCompletedOrder(from payload: CustomerV2DashboardPayload) -> Int? {
        guard let timestamp = (payload.orders?.pastItems ?? [])
            .filter({ $0.status?.lowercased() == "completed" })
            .compactMap(\.sortTime)
            .max()
        else { return nil }

        let lastOrderDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let days = Calendar.current.dateComponents([.day], from: lastOrderDate, to: Date()).day
        return days.map { max(0, $0) }
    }

    private static func categoryImages(for name: String) -> (image: String, mark: String) {
        let key = name.lowercased()
        if key.contains("yogurt") {
            return ("StoreYogurt", "MarkYogurt")
        }
        if key.contains("smoothie") {
            return ("StoreSmoothie", "MarkSmoothie")
        }
        if key.contains("dessert") || key.contains("crepe") || key.contains("ice cream") {
            return ("StoreDessert", "MarkDessert")
        }
        return ("StoreOats", "MarkOats")
    }

    private static func localImageName(for name: String, category: StoreCategory) -> String {
        let key = name.lowercased()
        if key.contains("blueberry") && key.contains("go") { return "ProductBlueberryGo" }
        if key.contains("peach") && key.contains("go") { return "ProductPeachGo" }
        if key.contains("pineapple") && key.contains("go") { return "ProductPineappleGo" }
        if key.contains("tirami") { return "ProductTiramiOats" }
        if key.contains("cappuccin") { return "ProductCappuccinOats" }
        if key.contains("cocon") { return "ProductCoconOats" }
        if key.contains("caramel") && key.contains("apple") { return "ProductCaramelApplePie" }
        if key.contains("cookie") { return "ProductCookieCookie" }
        if key.contains("candy") { return "ProductCandyCloud" }
        if key.contains("tropical") && key.contains("apple") { return "ProductTropicalApple" }
        if key.contains("tropical") && key.contains("berry") { return "ProductTropicalBerry" }
        if key.contains("tropical") && key.contains("mango") { return "ProductTropicalMango" }
        if key.contains("tropical") && key.contains("nougat") { return "ProductTropicalNougat" }
        if key.contains("blueberry") { return "ProductGreekYogurtBlueberry" }
        if key.contains("pineapple") { return "ProductGreekYogurtPineapple" }
        if key.contains("mango") { return "ProductGreekYogurtMango" }
        if key.contains("lychee") { return "ProductGreekYogurtLychee" }
        if key.contains("kiwi") { return "ProductGreekYogurtKiwi" }
        if key.contains("crepe") { return "ProductProteinCrepe" }
        return category.imageName
    }

    private static func nutritionValues(from macro: String) -> (protein: String, calories: String, sugar: String) {
        let parts = macro
            .replacingOccurrences(of: "|", with: "·")
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let proteinPart = parts.first { $0.localizedCaseInsensitiveContains("protein") }
        let caloriePart = parts.first {
            $0.localizedCaseInsensitiveContains("kcal") || $0.localizedCaseInsensitiveContains("cal")
        }
        let sugarPart = parts.first { $0.localizedCaseInsensitiveContains("sugar") }

        return (
            protein: compactNutritionValue(proteinPart, removing: ["protein"]) ?? nonEmpty(macro) ?? "-",
            calories: compactNutritionValue(caloriePart, removing: ["kcal", "calories", "cal"]) ?? "-",
            sugar: compactNutritionValue(sugarPart, removing: ["sugar"]) ?? "-"
        )
    }

    private static func compactNutritionValue(_ value: String?, removing labels: [String]) -> String? {
        guard var value = nonEmpty(value) else { return nil }
        for label in labels {
            value = value.replacingOccurrences(of: label, with: "", options: [.caseInsensitive])
        }

        return nonEmpty(value)
    }

    private static func webURL(from value: String?) -> URL? {
        guard let value = nonEmpty(value) else { return nil }

        if value.localizedCaseInsensitiveContains("/images/storefront/experience/fitbites-welcome.webp") {
            return nil
        }

        let baseURL = URL(string: "https://app.fitbites.com.vn")!

        if var components = URLComponents(string: value), components.scheme != nil {
            if components.host == "localhost" || components.host == "127.0.0.1" {
                components.scheme = baseURL.scheme
                components.host = baseURL.host
                components.port = baseURL.port
            }

            return components.url
        }

        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func streakDays(from label: String?) -> Int? {
        guard let label else { return nil }
        let digits = label.filter(\.isNumber)
        return Int(digits)
    }

    private static func orderCount(from stats: [CustomerV2DashboardPayload.Stat]?) -> Int {
        guard let value = statValue("Orders", in: stats) else { return 0 }
        let digits = value.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private static func statValue(_ label: String, in stats: [CustomerV2DashboardPayload.Stat]?) -> String? {
        stats?.first { ($0.label ?? "").caseInsensitiveCompare(label) == .orderedSame }?.value?.value
    }

    private static func joinedDateLabel(from value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return value }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private static func slug(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct LocalCatalogRepository: CatalogRepository {
    func catalog() -> StoreCatalog {
        StoreCatalog(
            categories: FixtureCatalog.categories,
            products: FixtureCatalog.products,
            featuredProductID: "tirami-oats"
        )
    }
}

struct LocalRewardsRepository: RewardsRepository {
    func rewards() -> RewardsProgress {
        RewardsProgress(
            level: 1,
            xp: 0,
            xpToNext: 500,
            levelTarget: 500,
            loyaltyStamps: 0,
            loyaltyTarget: 9,
            rewardsReady: 0,
            unannouncedFreeFitbitesRewardID: nil,
            freeFitbitesRewards: [],
            freeFitbitesHistory: [],
            freeFitbitesRedemptionEnabled: false,
            achievements: [],
            ricoWallet: RicoWalletSummary(balance: 0, todayEarned: 0, dailyMax: 5),
            ricoStoreItems: []
        )
    }
}

enum FixtureCatalog {
    static let categories = [
        StoreCategory(id: "oats", name: "Protein Oats", label: "PROTEIN OATS", intro: "Cold oats. Slow mornings. Protein without the noise.", imageName: "StoreOats", markName: "MarkOats"),
        StoreCategory(id: "yogurt", name: "Greek Yogurt", label: "GREEK YOGURT", intro: "Thick, bright, homemade. The base of half our obsessions.", imageName: "StoreYogurt", markName: "MarkYogurt"),
        StoreCategory(id: "smoothies", name: "Greek Smoothie", label: "GREEK SMOOTHIES", intro: "Greek smoothie with fruit and our signature Greek yogurt.", imageName: "StoreSmoothie", markName: "MarkSmoothie"),
        StoreCategory(id: "desserts", name: "Protein Desserts", label: "PROTEIN DESSERTS", intro: "Small rewards with a Fitbites spine.", imageName: "StoreDessert", markName: "MarkDessert")
    ]

    static let products = [
        product("blueberry-go", 101, "Blueberry Go", "oats", "Creamy overnight oats layered with rich blueberry coulis.", "Rolled oats, Greek yogurt, whey protein, blueberry coulis.", "17g", "225", "Low", "Daily Go", 45_000, imageName: "ProductBlueberryGo"),
        product("peach-go", 102, "Peach Go", "oats", "Silky oats infused with sweet peach coulis.", "Rolled oats, Greek yogurt, whey protein, peach coulis.", "17g", "225", "Low", "Daily Go", 45_000, imageName: "ProductPeachGo"),
        product("pineapple-go", 103, "Pineapple Go", "oats", "Chilled oats with bright pineapple coulis, fresh, tropical, and clean fuel.", "Rolled oats, Greek yogurt, whey protein, pineapple coulis.", "17g", "225", "Low", "Daily Go", 45_000, imageName: "ProductPineappleGo"),
        product("tirami-oats", 104, "Tirami'Oats", "oats", "Rich chocolate oats with real cacao, deep, smooth, and dangerously close to dessert.", "Rolled oats, Greek yogurt, whey protein, cacao.", "17g", "225", "Low", "Daily Classic", 55_000, imageName: "ProductTiramiOats"),
        product("cappuccin-oats", 105, "Cappuccin'Oats", "oats", "High in protein. Creamy, indulgent with an iced cappuccino touch.", "Rolled oats, Greek yogurt, whey protein, coffee.", "17g", "225", "Low", "Daily Classic", 55_000, imageName: "ProductCappuccinOats"),
        product("cocon-oats", 106, "Cocon'Oats", "oats", "Chocolate meets coconut in a creamy, indulgent blend.", "Rolled oats, Greek yogurt, whey protein, coconut, cacao.", "17g", "225", "Low", "Daily Classic", 55_000, imageName: "ProductCoconOats"),
        product("caramel-apple-pie", 107, "Caramel Apple Pie", "oats", "Warm baked apple with a caramel touch.", "Rolled oats, Greek yogurt, whey protein, apple, caramel.", "17g", "225", "Low", "Daily Classic", 55_000, imageName: "ProductCaramelApplePie"),
        product("cookie-cookie", 108, "The Cookie-Cookie", "oats", "Creamy oats with a cookie butter vibe.", "Rolled oats, Greek yogurt, whey protein, cookie butter.", "17g", "225", "Low", "Daily Classic", 55_000, imageName: "ProductCookieCookie"),
        product("candy-cloud", 109, "Candy Cloud", "oats", "Creamy, delicious and indulgent. High in protein.", "Rolled oats, Greek yogurt, whey protein, candy cloud mix.", "17g", "225", "Low", "Daily Classic", 60_000, imageName: "ProductCandyCloud"),
        product("tropical-apple", 110, "Tropical Apple", "oats", "Bright green apple with a fresh tropical edge.", "Rolled oats, Greek yogurt, whey protein, apple.", "17g", "225", "Low", "Daily Tropical", 65_000, imageName: "ProductTropicalApple"),
        product("tropical-berry", 111, "Tropical Berry", "oats", "Berry-forward tropical oats with a creamy Fitbites finish.", "Rolled oats, Greek yogurt, whey protein, berry coulis.", "17g", "225", "Low", "Daily Tropical", 65_000, imageName: "ProductTropicalBerry"),
        product("tropical-mango", 112, "Tropical Mango", "oats", "Light mango oats, smooth, juicy, and clean.", "Rolled oats, Greek yogurt, whey protein, mango.", "17g", "225", "Low", "Daily Tropical", 65_000, imageName: "ProductTropicalMango"),
        product("tropical-nougat", 113, "Tropical Nougat", "oats", "Peach and nougat teaming up in this creamy creation.", "Rolled oats, Greek yogurt, whey protein, peach, nougat.", "17g", "225", "Low", "Daily Tropical", 65_000, imageName: "ProductTropicalNougat"),
        product("greek-yogurt-blueberry", 201, "BLUEBERRY", "yogurt", "Greek yogurt with blueberry coulis.", "Greek yogurt, blueberry coulis.", "16g", "225", "Low", "Greek Yogurt", 59_000, imageName: "ProductGreekYogurtBlueberry"),
        product("greek-yogurt-pineapple", 204, "PINEAPPLE", "yogurt", "Greek yogurt with pineapple.", "Greek yogurt, pineapple.", "16g", "225", "Low", "Greek Yogurt", 59_000, imageName: "ProductGreekYogurtPineapple"),
        product("greek-yogurt-mango", 202, "MANGO", "yogurt", "Greek yogurt with mango.", "Greek yogurt, mango.", "16g", "225", "Low", "Greek Yogurt", 59_000, imageName: "ProductGreekYogurtMango"),
        product("greek-yogurt-lychee", 205, "LYCHEE", "yogurt", "Greek yogurt with lychee.", "Greek yogurt, lychee.", "16g", "225", "Low", "Greek Yogurt", 59_000, imageName: "ProductGreekYogurtLychee"),
        product("greek-yogurt-kiwi", 203, "KIWI", "yogurt", "Greek yogurt with kiwi.", "Greek yogurt, kiwi.", "16g", "225", "Low", "Greek Yogurt", 59_000, imageName: "ProductGreekYogurtKiwi"),
        product("hazel-noir", 301, "HAZEL'NOIR", "desserts", "Protein ice cream with hazelnut and dark chocolate notes.", "Greek yogurt, whey protein, cacao, hazelnut.", "12g", "210", "Low", "Protein Ice Cream", 60_000),
        product("swiss-delight", 302, "SWISS DELIGHT", "desserts", "Protein ice cream with a creamy Swiss dessert profile.", "Greek yogurt, whey protein, cocoa.", "12g", "210", "Low", "Protein Ice Cream", 60_000),
        product("protein-crepe", 303, "Protein Crepe", "desserts", "A soft protein crepe with a clean cafe dessert profile.", "Egg, oat flour, whey protein, Greek yogurt, cacao.", "14g", "310", "Medium", "Protein Crepe", 45_000, imageName: "ProductProteinCrepe"),
        product("banana-choco", 401, "BANANA CHOCO", "smoothies", "Greek smoothie with banana, chocolate, and a clean protein finish.", "Greek yogurt, whey protein, banana, cacao.", "16g", "260", "Low", "Greek Smoothie", 75_000, toppings: []),
        product("berry-cheesecake", 402, "BERRY CHEESECAKE", "smoothies", "Greek smoothie with berry cheesecake energy, creamy and cold.", "Greek yogurt, whey protein, berries, cheesecake profile.", "16g", "260", "Low", "Greek Smoothie", 75_000, toppings: []),
        product("mango-delight", 403, "MANGO DELIGHT", "smoothies", "Greek smoothie with mango, bright, creamy, and protein-first.", "Greek yogurt, whey protein, mango.", "16g", "260", "Low", "Greek Smoothie", 75_000, toppings: [])
    ]

    static let toppings = [
        StoreTopping(id: "greek-yogurt-50g", toppingID: 501, name: "Greek Yogurt 50g", category: "Greek Yogurt", priceVND: 15_000),
        StoreTopping(id: "greek-yogurt-100g", toppingID: 502, name: "Greek Yogurt 100g", category: "Greek Yogurt", priceVND: 30_000),
        StoreTopping(id: "apple", toppingID: 503, name: "Apple", category: "Extra Fruits", priceVND: 10_000),
        StoreTopping(id: "banana", toppingID: 504, name: "Banana", category: "Extra Fruits", priceVND: 10_000),
        StoreTopping(id: "strawberry", toppingID: 505, name: "Strawberry", category: "Extra Fruits", priceVND: 15_000),
        StoreTopping(id: "mango", toppingID: 506, name: "Mango", category: "Extra Fruits", priceVND: 15_000),
        StoreTopping(id: "baked-oats", toppingID: 507, name: "Baked Oats", category: "Crunch", priceVND: 10_000),
        StoreTopping(id: "sliced-almonds", toppingID: 508, name: "Sliced Almonds", category: "Crunch", priceVND: 10_000),
        StoreTopping(id: "dark-chocolate", toppingID: 509, name: "Dark Chocolate", category: "Crunch", priceVND: 12_000),
        StoreTopping(id: "chocolate-nougat", toppingID: 510, name: "Chocolate Nougat", category: "Crunch", priceVND: 10_000),
        StoreTopping(id: "cacao-nibs", toppingID: 511, name: "Cacao Nibs", category: "Crunch", priceVND: 12_000),
        StoreTopping(id: "homemade-granola", toppingID: 512, name: "Homemade Granola", category: "Crunch", priceVND: 15_000),
        StoreTopping(id: "organic-goji-berries", toppingID: 513, name: "Organic Goji Berries", category: "Crunch", priceVND: 15_000),
        StoreTopping(id: "almonds-covered-with-chocolate", toppingID: 514, name: "Almonds covered with chocolate", category: "Crunch", priceVND: 17_000),
        StoreTopping(id: "protein-cacao-nuts-butter", toppingID: 515, name: "Protein Cacao & Nuts Butter", category: "Nut Butter", priceVND: 19_000),
        StoreTopping(id: "protein-cookies-butter", toppingID: 516, name: "Protein Cookies Butter", category: "Nut Butter", priceVND: 19_000),
        StoreTopping(id: "almond-butter", toppingID: 517, name: "Almond Butter", category: "Nut Butter", priceVND: 17_000),
        StoreTopping(id: "cashew-butter", toppingID: 518, name: "Cashew Butter", category: "Nut Butter", priceVND: 17_000),
        StoreTopping(id: "cacao", toppingID: 519, name: "Cacao", category: "Extras", priceVND: 5_000),
        StoreTopping(id: "honey", toppingID: 520, name: "Honey", category: "Extras", priceVND: 5_000),
        StoreTopping(id: "cinnamon", toppingID: 521, name: "Cinnamon", category: "Extras", priceVND: 0)
    ]

    private static func product(
        _ id: String,
        _ inventoryItemID: Int,
        _ name: String,
        _ categoryID: String,
        _ description: String,
        _ ingredients: String,
        _ protein: String,
        _ calories: String,
        _ sugar: String,
        _ badge: String,
        _ priceVND: Int,
        toppings: [StoreTopping] = FixtureCatalog.toppings,
        imageName: String? = nil
    ) -> StoreProduct {
        let category = categories.first { $0.id == categoryID } ?? categories[1]
        return StoreProduct(
            id: id,
            inventoryItemID: inventoryItemID,
            name: name,
            categoryID: categoryID,
            description: description,
            ingredients: ingredients,
            protein: protein,
            calories: calories,
            sugar: sugar,
            badge: badge,
            priceVND: priceVND,
            imageName: imageName ?? category.imageName,
            imageURL: nil,
            markName: category.markName,
            isAvailable: true,
            pickupOnly: false,
            toppings: toppings
        )
    }
}
