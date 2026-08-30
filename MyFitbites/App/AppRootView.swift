import PhotosUI
import SwiftUI
import UIKit

struct DebugVnpayPaymentSession: Identifiable {
    let id = UUID()
    let url: URL
    let attemptUUID: String
}

struct AppRootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ZStack {
                TabView(selection: $appState.selectedTab) {
                    NavigationStack(path: $appState.homePath) {
                        HomeView()
                    }
                    .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }
                    .tag(AppTab.home)

                    NavigationStack(path: $appState.orderPath) {
                        StoreView()
                    }
                    .tabItem { Label(AppTab.order.title, systemImage: AppTab.order.symbol) }
                    .tag(AppTab.order)

                    NavigationStack(path: $appState.progressPath) {
                        ProgressTabView()
                    }
                    .tabItem { Label(AppTab.progress.title, systemImage: AppTab.progress.symbol) }
                    .tag(AppTab.progress)

                    NavigationStack(path: $appState.rewardsPath) {
                        RewardsView()
                    }
                    .tabItem { Label(AppTab.rewards.title, systemImage: AppTab.rewards.symbol) }
                    .tag(AppTab.rewards)

                    NavigationStack(path: $appState.profilePath) {
                        ProfileView()
                    }
                    .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.symbol) }
                    .tag(AppTab.profile)
                }
                .tint(FBColors.cookieOrange)
                .toolbarBackground(FBColors.ivory, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .opacity(appState.isMainAppVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.92).delay(0.08), value: appState.isLaunchSplashVisible)
                .animation(.easeInOut(duration: 0.22), value: appState.authenticationStatus)

                if appState.shouldShowAuthentication {
                    CustomerAuthenticationView()
                        .environmentObject(appState)
                        .transition(.opacity)
                }
            }

            if appState.isLaunchSplashVisible {
                AppLaunchSplashView()
                    .transition(.opacity)
            }
        }
        .task {
            await appState.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await appState.refreshAuthenticationSessionIfNeededForForeground()
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var orderPath = NavigationPath()
    @Published var progressPath = NavigationPath()
    @Published var rewardsPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    @Published var cart = CartStore()
    @Published var pendingStoreProductID: String?
    @Published var shouldOpenCartOnOrderTab = false
    @Published var customerProfile = CustomerProfile(
        name: "MyFitbites Member",
        phone: "",
        email: "",
        avatar: LocalAvatar.default
    )
    @Published var savedAddresses: [SavedAddress] = [
        SavedAddress(id: "home", label: "Home", detail: "Thao Dien, Thu Duc City", note: "Leave with reception if needed.", systemImage: "house"),
        SavedAddress(id: "work", label: "Work", detail: "District 1, Ho Chi Minh City", note: "Call when downstairs.", systemImage: "briefcase"),
        SavedAddress(id: "gym", label: "Gym", detail: "Fitbites training spot", note: "After 6 PM preferred.", systemImage: "figure.strengthtraining.traditional")
    ] {
        didSet { persistSavedAddresses() }
    }
    @Published var selectedAddressID = "home" {
        didSet { UserDefaults.standard.set(selectedAddressID, forKey: selectedAddressDefaultsKey) }
    }
    @Published var dashboardHeroWeatherCondition: DashboardHeroWeatherCondition?
    @Published var isLaunchSplashVisible = true
    @Published var authenticationStatus: CustomerAuthenticationStatus = .unknown
    @Published var authenticationMode: CustomerAuthenticationMode = .signIn
    @Published var authenticationErrorMessage: String?
    @Published var authenticationFieldErrors = AuthFieldErrors()
    @Published var isAuthenticationSubmitting = false
    @Published var isCheckoutSubmitting = false
    @Published var checkoutErrorMessage: String?
    @Published var lastSubmittedOrder: CustomerV2CheckoutPayload.Order?
    @Published var deliveryQuoteErrorMessage: String?
    @Published var tooLabProgress: TooLabProgress = .empty
    @Published var tooLabErrorMessage: String?
    @Published var ricoStoreErrorMessage: String?
    @Published var ricoPurchaseIDsInFlight: Set<String> = []
    @Published var currentCustomerID: Int?
    #if DEBUG
    @Published var debugVnpayPaymentSession: DebugVnpayPaymentSession?
    @Published var debugVnpayPaymentStatus: CustomerV2PaymentStatusPayload?
    @Published var debugVnpayMessage: String?
    @Published var isDebugVnpaySubmitting = false
    @Published var isDebugVnpayStatusRefreshing = false
    #endif

    let dashboardRepository: DashboardRepository
    let catalogRepository: CatalogRepository
    let rewardsRepository: RewardsRepository
    let dashboardHeroWeatherProvider: any DashboardHeroWeatherProviding
    let customerAPIClient: CustomerV2APIClient?
    private var ricoPurchaseIntentKeys: [String: String] = [:]
    private var hasBootstrapped = false
    private var lastForegroundSessionRefreshAt: Date?
    private let avatarPresetDefaultsKey = "myfitbites.local.avatar.preset"
    private let avatarPhotoDefaultsKey = "myfitbites.local.avatar.photo"
    private let savedAddressesDefaultsKey = "myfitbites.local.saved-addresses"
    private let selectedAddressDefaultsKey = "myfitbites.local.selected-address"
    #if DEBUG
    private let debugVnpayAttemptUUIDDefaultsKey = "myfitbites.debug.vnpay.attempt-uuid"
    #endif

    var shouldShowAuthentication: Bool {
        (authenticationStatus == .guest || authenticationStatus == .unavailable) && !isLaunchSplashVisible
    }

    var isMainAppVisible: Bool {
        authenticationStatus == .authenticated && !isLaunchSplashVisible
    }

    var canAttemptRicoStorePurchase: Bool {
        authenticationStatus == .authenticated && customerAPIClient != nil
    }

    init(
        dashboardRepository: DashboardRepository,
        catalogRepository: CatalogRepository,
        rewardsRepository: RewardsRepository,
        dashboardHeroWeatherProvider: any DashboardHeroWeatherProviding = UnavailableDashboardHeroWeatherProvider(),
        customerAPIClient: CustomerV2APIClient? = nil
    ) {
        self.dashboardRepository = dashboardRepository
        self.catalogRepository = catalogRepository
        self.rewardsRepository = rewardsRepository
        self.dashboardHeroWeatherProvider = dashboardHeroWeatherProvider
        self.customerAPIClient = customerAPIClient
        customerProfile.avatar = loadLocalAvatar()
        savedAddresses = loadSavedAddresses()
        selectedAddressID = UserDefaults.standard.string(forKey: selectedAddressDefaultsKey) ?? savedAddresses.first?.id ?? "home"
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        async let minimumSplash: Void = holdLaunchSplash()
        await refreshAuthenticationSession()

        let customerRefresh = Task { [weak self] in
            guard let self, self.authenticationStatus == .authenticated else { return }
            await self.refreshCustomerData()
        }

        _ = await minimumSplash

        withAnimation(.easeInOut(duration: 0.78)) {
            isLaunchSplashVisible = false
        }

        _ = await customerRefresh.value
        #if DEBUG
        await recoverDebugVnpayPaymentIfNeeded()
        #endif
    }

    func refreshDashboardHeroWeather() async {
        await dashboardHeroWeatherProvider.refreshIfNeeded()
        dashboardHeroWeatherCondition = dashboardHeroWeatherProvider.currentCondition
    }

    func refreshCustomerData() async {
        var didRefresh = false

        didRefresh = await refreshDashboardAndRewardsCaches() || didRefresh

        if let repository = catalogRepository as? CustomerDataRefreshing {
            await repository.refresh()
            didRefresh = true
        }

        await refreshTooLabProgress()
        didRefresh = true

        if didRefresh {
            objectWillChange.send()
        }
    }

    func refreshDashboardAndRewards() async {
        if await refreshDashboardAndRewardsCaches() {
            objectWillChange.send()
        }
    }

    func refreshTooLabProgress() async {
        guard let customerAPIClient, authenticationStatus == .authenticated else { return }

        do {
            let envelope = try await customerAPIClient.tooLabSummary()
            tooLabProgress = CustomerV2Mapper.tooLabProgress(from: envelope.tooLab, fallback: tooLabProgress)
            tooLabErrorMessage = nil
        } catch {
            tooLabErrorMessage = error.localizedDescription
        }
    }

    func completeTooLabGame(identifier: String, score: Int = 0) async -> Int {
        guard let customerAPIClient, authenticationStatus == .authenticated else { return 0 }

        do {
            let payload = try await customerAPIClient.completeTooLabGame(identifier: identifier, score: score)
            tooLabProgress = CustomerV2Mapper.tooLabProgress(from: payload.summary, fallback: tooLabProgress)
            tooLabErrorMessage = nil
            objectWillChange.send()
            return payload.awardedLxp ?? 0
        } catch {
            tooLabErrorMessage = error.localizedDescription
            return 0
        }
    }

    func purchaseTooLabPrototype(identifier: String) async -> Int {
        guard let customerAPIClient, authenticationStatus == .authenticated else { return 0 }

        do {
            let payload = try await customerAPIClient.purchaseTooLabPrototype(
                identifier: identifier,
                idempotencyKey: "ios-too-lab-prototype-\(identifier)-\(UUID().uuidString)"
            )
            tooLabProgress = CustomerV2Mapper.tooLabProgress(from: payload.summary, fallback: tooLabProgress)
            tooLabErrorMessage = nil
            objectWillChange.send()
            return payload.awardedLxp ?? 0
        } catch {
            tooLabErrorMessage = error.localizedDescription
            return 0
        }
    }

    func submitTooLabPrototypeFeedback(purchaseID: String, report: String) async -> Int {
        guard let customerAPIClient, authenticationStatus == .authenticated else { return 0 }

        do {
            let payload = try await customerAPIClient.submitTooLabPrototypeFeedback(purchaseID: purchaseID, report: report)
            tooLabProgress = CustomerV2Mapper.tooLabProgress(from: payload.summary, fallback: tooLabProgress)
            tooLabErrorMessage = nil
            objectWillChange.send()
            return payload.awardedLxp ?? 0
        } catch {
            tooLabErrorMessage = error.localizedDescription
            return 0
        }
    }

    func purchaseRicoStoreItem(_ item: RicoStoreItem) async {
        guard let customerAPIClient, item.isAvailable, !item.isOwned else { return }
        guard !ricoPurchaseIDsInFlight.contains(item.id) else { return }

        ricoStoreErrorMessage = nil
        let idempotencyKey = ricoPurchaseIntentKeys[item.id] ?? "ios-rico-\(UUID().uuidString)"
        ricoPurchaseIntentKeys[item.id] = idempotencyKey
        ricoPurchaseIDsInFlight.insert(item.id)
        defer { ricoPurchaseIDsInFlight.remove(item.id) }

        do {
            _ = try await customerAPIClient.purchaseRicoStoreItem(
                id: item.id,
                idempotencyKey: idempotencyKey
            )

            ricoPurchaseIntentKeys[item.id] = nil
            if let repository = rewardsRepository as? CustomerDataRefreshing {
                await repository.refresh()
            }
            objectWillChange.send()
        } catch {
            ricoStoreErrorMessage = customerFacingRicoPurchaseError(error)
        }
    }

    private func customerFacingRicoPurchaseError(_ error: Error) -> String {
        if let apiError = error as? CustomerV2APIError, let message = apiError.errorDescription {
            return message
        }

        return "Rico's vault is busy. Try again."
    }

    private func refreshDashboardAndRewardsCaches() async -> Bool {
        if
            let customerAPIClient,
            let payload = try? await customerAPIClient.dashboard()
        {
            (dashboardRepository as? CustomerV2DashboardPayloadCaching)?.applyDashboardPayload(payload)
            (rewardsRepository as? CustomerV2DashboardPayloadCaching)?.applyDashboardPayload(payload)
            if let repository = rewardsRepository as? CustomerDataRefreshing {
                await repository.refresh()
            }
            return true
        } else {
            var didRefresh = false

            if let repository = dashboardRepository as? CustomerDataRefreshing {
                await repository.refresh()
                didRefresh = true
            }

            if let repository = rewardsRepository as? CustomerDataRefreshing {
                await repository.refresh()
                didRefresh = true
            }

            return didRefresh
        }
    }

    func refreshAuthenticationSession() async {
        guard let customerAPIClient else {
            authenticationStatus = .unavailable
            return
        }

        do {
            let payload = try await customerAPIClient.sessionData()
            if payload.authenticated, let user = payload.user {
                applyAuthenticatedUser(user)
                authenticationStatus = .authenticated
            } else {
                currentCustomerID = nil
                tooLabProgress = .empty
                authenticationStatus = .guest
            }
        } catch {
            currentCustomerID = nil
            tooLabProgress = .empty
            authenticationStatus = .unavailable
        }
    }

    func refreshAuthenticationSessionIfNeededForForeground() async {
        guard authenticationStatus == .authenticated else { return }

        let now = Date()
        if let lastForegroundSessionRefreshAt, now.timeIntervalSince(lastForegroundSessionRefreshAt) < 300 {
            return
        }

        lastForegroundSessionRefreshAt = now
        await refreshAuthenticationSession()
    }

    func submitSignIn(phone: String, password: String) async {
        guard let customerAPIClient else { return }
        authenticationErrorMessage = nil
        authenticationFieldErrors = AuthFieldErrors()

        var fieldErrors = AuthFieldErrors()
        if phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fieldErrors.phone = "Enter your phone number."
        }
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fieldErrors.password = "Enter your password."
        }
        if fieldErrors.hasErrors {
            authenticationFieldErrors = fieldErrors
            return
        }

        isAuthenticationSubmitting = true
        defer { isAuthenticationSubmitting = false }

        do {
            let payload = try await customerAPIClient.login(phone: phone, password: password)
            guard let user = payload.user else {
                throw CustomerV2APIError.server("Fitbites could not load your profile.")
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                applyAuthenticatedUser(user)
                authenticationStatus = .authenticated
            }
            await refreshCustomerData()
        } catch {
            authenticationFieldErrors = signInErrors(from: error)
            if !authenticationFieldErrors.hasErrors {
                authenticationErrorMessage = "We couldn’t sign you in. Please try again."
            }
        }
    }

    func submitSignUp(name: String, phone: String, email: String, password: String) async {
        guard let customerAPIClient else { return }
        authenticationErrorMessage = nil
        authenticationFieldErrors = AuthFieldErrors()
        isAuthenticationSubmitting = true
        defer { isAuthenticationSubmitting = false }

        do {
            let payload = try await customerAPIClient.register(
                name: name,
                phone: phone,
                email: email,
                password: password
            )
            guard let user = payload.user else {
                throw CustomerV2APIError.server("Fitbites could not load your profile.")
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                applyAuthenticatedUser(user)
                authenticationStatus = .authenticated
            }
            await refreshCustomerData()
        } catch {
            authenticationErrorMessage = "We couldn’t create your account. Please try again."
        }
    }

    func clearAuthenticationFieldError(_ field: AuthField) {
        switch field {
        case .phone:
            authenticationFieldErrors.phone = nil
        case .password:
            authenticationFieldErrors.password = nil
        }
    }

    func signOut() async {
        await customerAPIClient?.logout()
        currentCustomerID = nil
        tooLabProgress = .empty
        authenticationErrorMessage = nil
        authenticationFieldErrors = AuthFieldErrors()

        withAnimation(.easeInOut(duration: 0.22)) {
            authenticationMode = .signIn
            authenticationStatus = .guest
        }
    }

    private func signInErrors(from error: Error) -> AuthFieldErrors {
        guard
            let apiError = error as? CustomerV2APIError,
            case let CustomerV2APIError.validation(_, fieldErrors) = apiError
        else {
            return AuthFieldErrors()
        }

        var errors = AuthFieldErrors()
        if let phoneErrors = fieldErrors["phone"] {
            errors.phone = phoneErrors.contains { $0.localizedCaseInsensitiveContains("required") }
                ? "Enter your phone number."
                : nil
            if errors.phone == nil {
                errors.password = "That phone number or password doesn’t match."
            }
        }
        if let passwordErrors = fieldErrors["password"] {
            errors.password = passwordErrors.contains { $0.localizedCaseInsensitiveContains("required") }
                ? "Enter your password."
                : errors.password
        }
        return errors
    }

    func updateCustomerAccount(
        name: String,
        phone: String,
        email: String,
        currentPassword: String,
        newPassword: String
    ) async throws {
        guard let customerAPIClient else {
            throw CustomerV2APIError.server("Fitbites account editing is not available right now.")
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCurrentPassword = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNewPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let isChangingPassword = !cleanNewPassword.isEmpty

        let payload = try await customerAPIClient.updateProfile(CustomerV2ProfileUpdateRequest(
            name: cleanName,
            phone: cleanPhone,
            email: cleanEmail.isEmpty ? nil : cleanEmail,
            currentPassword: isChangingPassword ? cleanCurrentPassword : nil,
            password: isChangingPassword ? cleanNewPassword : nil,
            passwordConfirmation: isChangingPassword ? cleanNewPassword : nil
        ))

        guard let user = payload.user else {
            throw CustomerV2APIError.server("Fitbites could not load your updated profile.")
        }

        applyAuthenticatedUser(user)
        objectWillChange.send()
    }

    func submitPickupCheckout() async {
        guard let customerAPIClient else {
            checkoutErrorMessage = "Fitbites checkout is not available right now."
            return
        }

        guard !cart.lines.isEmpty else {
            checkoutErrorMessage = "Your cart is empty."
            return
        }

        checkoutErrorMessage = nil
        lastSubmittedOrder = nil
        isCheckoutSubmitting = true
        defer { isCheckoutSubmitting = false }

        do {
            let request = CustomerV2CheckoutRequest(
                cart: cart.lines.map { line in
                    CustomerV2CheckoutRequest.Item(
                        id: line.product.inventoryItemID,
                        quantity: line.quantity,
                        toppings: line.toppings.map { CustomerV2CheckoutRequest.Topping(id: $0.toppingID) },
                        customerNotes: nil
                    )
                },
                checkoutToken: "ios-\(UUID().uuidString)",
                fulfillmentMethod: "in_store_pickup",
                paymentMethod: "pay_at_counter",
                customerNotes: nil,
                coordinateSource: nil,
                deliveryZoneId: nil,
                recipientName: nil,
                deliveryPhone: nil,
                deliveryAddress: nil,
                deliveryNotes: nil,
                deliveryLatitude: nil,
                deliveryLongitude: nil,
                deliveryLocationAccuracyM: nil
            )

            let payload = try await customerAPIClient.checkout(request)
            lastSubmittedOrder = payload.order
            cart.clear()
        } catch {
            checkoutErrorMessage = error.localizedDescription
        }
    }

    func reorder(_ order: CustomerOrderSummary) {
        let catalog = catalogRepository.catalog()
        let productsByInventoryID = Dictionary(uniqueKeysWithValues: catalog.products.map { ($0.inventoryItemID, $0) })

        cart.clear()

        for item in order.reorderItems {
            guard let product = productsByInventoryID[item.productID] else { continue }
            let toppingIDSet = Set(item.toppingIDs)
            let toppings = product.toppings.filter { toppingIDSet.contains($0.toppingID) }
            cart.add(product, toppings: toppings, quantity: item.quantity)
        }

        guard cart.itemCount > 0 else { return }

        shouldOpenCartOnOrderTab = true
        selectedTab = .order
    }

    func quoteDeliveryAddress(
        latitude: Double,
        longitude: Double,
        accuracy: Double?,
        coordinateSource: DeliveryCoordinateSource
    ) async throws -> CustomerV2DeliveryQuotePayload {
        guard let customerAPIClient else {
            throw CustomerV2APIError.server("Fitbites delivery quote is not available right now.")
        }

        deliveryQuoteErrorMessage = nil

        do {
            return try await customerAPIClient.deliveryQuote(CustomerV2DeliveryQuoteRequest(
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                coordinateSource: coordinateSource.apiValue
            ))
        } catch {
            deliveryQuoteErrorMessage = error.localizedDescription
            throw error
        }
    }

    func saveConfirmedDeliveryAddress(_ address: SavedAddress) {
        guard address.isConfirmedForDelivery else { return }

        if let index = savedAddresses.firstIndex(where: { $0.id == address.id }) {
            savedAddresses[index] = address
        } else {
            savedAddresses.insert(address, at: 0)
        }

        selectedAddressID = address.id
        persistSavedAddresses()
    }

    func selectSavedAddress(_ address: SavedAddress) {
        selectedAddressID = address.id
        UserDefaults.standard.set(address.id, forKey: selectedAddressDefaultsKey)
    }

    func submitDeliveryCheckout() async {
        guard let customerAPIClient else {
            checkoutErrorMessage = "Fitbites checkout is not available right now."
            return
        }

        guard !cart.lines.isEmpty else {
            checkoutErrorMessage = "Your cart is empty."
            return
        }

        guard
            let address = savedAddresses.first(where: { $0.id == selectedAddressID }),
            address.isConfirmedForDelivery,
            let latitude = address.latitude,
            let longitude = address.longitude,
            let coordinateSource = address.coordinateSource,
            let deliveryZoneID = address.deliveryZoneID
        else {
            checkoutErrorMessage = "Choose a confirmed delivery address first."
            return
        }

        checkoutErrorMessage = nil
        lastSubmittedOrder = nil
        isCheckoutSubmitting = true
        defer { isCheckoutSubmitting = false }

        do {
            let request = CustomerV2CheckoutRequest(
                cart: cart.lines.map { line in
                    CustomerV2CheckoutRequest.Item(
                        id: line.product.inventoryItemID,
                        quantity: line.quantity,
                        toppings: line.toppings.map { CustomerV2CheckoutRequest.Topping(id: $0.toppingID) },
                        customerNotes: nil
                    )
                },
                checkoutToken: "ios-\(UUID().uuidString)",
                fulfillmentMethod: "delivery",
                paymentMethod: "cash_on_delivery",
                customerNotes: nil,
                coordinateSource: coordinateSource.apiValue,
                deliveryZoneId: deliveryZoneID,
                recipientName: customerProfile.name,
                deliveryPhone: customerProfile.phone,
                deliveryAddress: formattedCheckoutAddress(address),
                deliveryNotes: address.note.isEmpty ? nil : address.note,
                deliveryLatitude: latitude,
                deliveryLongitude: longitude,
                deliveryLocationAccuracyM: coordinateSource == .deviceLocation ? address.locationAccuracyM : nil
            )

            let payload = try await customerAPIClient.checkout(request)
            lastSubmittedOrder = payload.order
            cart.clear()
        } catch {
            checkoutErrorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func submitDebugVnpaySandboxDeliveryCheckout() async {
        guard let customerAPIClient else {
            checkoutErrorMessage = "Fitbites checkout is not available right now."
            return
        }

        guard !cart.lines.isEmpty else {
            checkoutErrorMessage = "Your cart is empty."
            return
        }

        guard
            let address = savedAddresses.first(where: { $0.id == selectedAddressID }),
            address.isConfirmedForDelivery,
            let latitude = address.latitude,
            let longitude = address.longitude,
            let coordinateSource = address.coordinateSource,
            let deliveryZoneID = address.deliveryZoneID
        else {
            checkoutErrorMessage = "Choose a confirmed delivery address first."
            return
        }

        checkoutErrorMessage = nil
        debugVnpayMessage = nil
        debugVnpayPaymentStatus = nil
        isDebugVnpaySubmitting = true
        defer { isDebugVnpaySubmitting = false }

        do {
            let checkoutToken = "ios-vnpay-sandbox-\(UUID().uuidString)"
            let checkout = try await customerAPIClient.checkout(CustomerV2CheckoutRequest(
                cart: cart.lines.map { line in
                    CustomerV2CheckoutRequest.Item(
                        id: line.product.inventoryItemID,
                        quantity: line.quantity,
                        toppings: line.toppings.map { CustomerV2CheckoutRequest.Topping(id: $0.toppingID) },
                        customerNotes: nil
                    )
                },
                checkoutToken: checkoutToken,
                fulfillmentMethod: "delivery",
                paymentMethod: "vnpay",
                customerNotes: "INTERNAL VNPAY SANDBOX VALIDATION",
                coordinateSource: coordinateSource.apiValue,
                deliveryZoneId: deliveryZoneID,
                recipientName: customerProfile.name,
                deliveryPhone: customerProfile.phone,
                deliveryAddress: formattedCheckoutAddress(address),
                deliveryNotes: address.note.isEmpty ? nil : address.note,
                deliveryLatitude: latitude,
                deliveryLongitude: longitude,
                deliveryLocationAccuracyM: coordinateSource == .deviceLocation ? address.locationAccuracyM : nil
            ))

            let initiation = try await customerAPIClient.initiateVnpayPayment(CustomerV2VnpayInitiationRequest(
                pendingOrderId: checkout.order.id,
                checkoutToken: checkoutToken,
                bankCode: nil
            ))

            lastSubmittedOrder = checkout.order
            cart.clear()
            UserDefaults.standard.set(initiation.paymentAttempt.uuid, forKey: debugVnpayAttemptUUIDDefaultsKey)
            debugVnpayMessage = "Waiting for VNPAY sandbox payment."
            debugVnpayPaymentSession = DebugVnpayPaymentSession(
                url: initiation.paymentUrl,
                attemptUUID: initiation.paymentAttempt.uuid
            )
            await refreshDebugVnpayPaymentStatus()
        } catch {
            checkoutErrorMessage = error.localizedDescription
            debugVnpayMessage = error.localizedDescription
        }
    }

    func refreshDebugVnpayPaymentStatus() async {
        guard let customerAPIClient else { return }
        guard let attemptUUID = UserDefaults.standard.string(forKey: debugVnpayAttemptUUIDDefaultsKey) else {
            debugVnpayMessage = "No open VNPAY sandbox attempt."
            return
        }

        isDebugVnpayStatusRefreshing = true
        defer { isDebugVnpayStatusRefreshing = false }

        do {
            let status = try await customerAPIClient.vnpayPaymentStatus(uuid: attemptUUID)
            debugVnpayPaymentStatus = status
            debugVnpayMessage = "Payment \(status.paymentAttempt.status). Order \(status.pendingOrder.paymentStatus)."

            if ["paid", "failed", "cancelled", "expired", "refunded"].contains(status.paymentAttempt.status) {
                UserDefaults.standard.removeObject(forKey: debugVnpayAttemptUUIDDefaultsKey)
            }
        } catch {
            debugVnpayMessage = error.localizedDescription
        }
    }

    private func recoverDebugVnpayPaymentIfNeeded() async {
        guard UserDefaults.standard.string(forKey: debugVnpayAttemptUUIDDefaultsKey) != nil else { return }
        await refreshDebugVnpayPaymentStatus()
    }
    #endif

    private func applyAuthenticatedUser(_ user: CustomerAuthUser) {
        if let currentCustomerID, currentCustomerID != user.id {
            tooLabProgress = .empty
        }

        currentCustomerID = user.id
        (dashboardRepository as? CustomerV2AuthenticatedUserCaching)?.applyAuthenticatedUser(user)
        customerProfile = CustomerProfile(
            name: user.name,
            phone: user.phone ?? customerProfile.phone,
            email: user.email ?? "",
            avatar: customerProfile.avatar
        )

        #if DEBUG
        UserDefaults.standard.set(RightNowDebugOverride.automatic.rawValue, forKey: RightNowPersistenceKey.debugOverride)
        #endif
    }

    func updateLocalAvatar(_ avatar: LocalAvatar) {
        customerProfile.avatar = avatar
        UserDefaults.standard.set(avatar.presetID, forKey: avatarPresetDefaultsKey)

        if let customPhotoData = avatar.customPhotoData {
            UserDefaults.standard.set(customPhotoData, forKey: avatarPhotoDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: avatarPhotoDefaultsKey)
        }
    }

    private func loadLocalAvatar() -> LocalAvatar {
        let presetID = UserDefaults.standard.string(forKey: avatarPresetDefaultsKey) ?? LocalAvatar.defaultPresetID
        let photoData = UserDefaults.standard.data(forKey: avatarPhotoDefaultsKey)
        return LocalAvatar(presetID: presetID, customPhotoData: photoData)
    }

    private func formattedCheckoutAddress(_ address: SavedAddress) -> String {
        let unit = address.apartmentUnit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return unit.isEmpty ? address.detail : "\(unit), \(address.detail)"
    }

    private func persistSavedAddresses() {
        if let data = try? JSONEncoder().encode(savedAddresses) {
            UserDefaults.standard.set(data, forKey: savedAddressesDefaultsKey)
        }
        UserDefaults.standard.set(selectedAddressID, forKey: selectedAddressDefaultsKey)
    }

    private func loadSavedAddresses() -> [SavedAddress] {
        if
            let data = UserDefaults.standard.data(forKey: savedAddressesDefaultsKey),
            let addresses = try? JSONDecoder().decode([SavedAddress].self, from: data),
            !addresses.isEmpty
        {
            return addresses
        }

        return [
            SavedAddress(id: "home", label: "Home", detail: "Thao Dien, Thu Duc City", note: "Leave with reception if needed.", systemImage: "house"),
            SavedAddress(id: "work", label: "Work", detail: "District 1, Ho Chi Minh City", note: "Call when downstairs.", systemImage: "briefcase"),
            SavedAddress(id: "gym", label: "Gym", detail: "Fitbites training spot", note: "After 6 PM preferred.", systemImage: "figure.strengthtraining.traditional")
        ]
    }

    private func holdLaunchSplash() async {
        try? await Task.sleep(nanoseconds: 1_950_000_000)
    }
}

enum CustomerAuthenticationStatus {
    case unknown
    case authenticated
    case guest
    case unavailable
}

enum CustomerAuthenticationMode {
    case signIn
    case signUp
}

enum AuthField {
    case phone
    case password
}

struct AuthFieldErrors {
    var phone: String?
    var password: String?

    var hasErrors: Bool {
        phone != nil || password != nil
    }
}

private struct AppLaunchSplashView: View {
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.94
    @State private var loadingProgress = 0.0

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: FBSpacing.lg) {
                Image("FitbitesLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 218)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(FBColors.line.opacity(0.28))

                        Capsule()
                            .fill(FBColors.cookieOrange)
                            .frame(width: proxy.size.width * loadingProgress)
                    }
                }
                .frame(width: 168, height: 4)
                .opacity(logoOpacity * 0.72)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                logoOpacity = 1
                logoScale = 1
            }
            withAnimation(.easeInOut(duration: 1.85)) {
                loadingProgress = 1
            }
        }
    }
}

private struct CustomerAuthenticationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var password = ""
    @State private var selectedAvatar = LocalAvatar.default
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var isSignUp: Bool { appState.authenticationMode == .signUp }

    var body: some View {
        ZStack {
            Color.white
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: FBSpacing.lg) {
                    Image("FitbitesLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 190)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .center, spacing: 8) {
                        Text("Welcome to MyFitbites")
                            .font(.custom("AvenirNext-Regular", size: 27))
                            .tracking(0.45)
                            .foregroundStyle(FBColors.charcoal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .multilineTextAlignment(.center)

                        Text("Order Fitbites. Earn XP. Collect stamps. Unlock rewards.")
                            .font(.custom("AvenirNext-Regular", size: 15))
                            .tracking(0.35)
                            .foregroundStyle(FBColors.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(spacing: 12) {
                        if isSignUp {
                            AuthTextField(title: "Name", text: $name, systemImage: "person.fill")
                        }

                        AuthTextField(
                            title: "Phone",
                            text: $phone,
                            systemImage: "phone.fill",
                            keyboardType: .phonePad,
                            errorMessage: appState.authenticationFieldErrors.phone
                        )

                        if isSignUp {
                            AuthTextField(title: "Email", text: $email, systemImage: "envelope.fill", keyboardType: .emailAddress)

                            AuthAvatarPicker(
                                avatar: $selectedAvatar,
                                selectedPhotoItem: $selectedPhotoItem
                            )
                        }

                        AuthSecureField(
                            title: "Password",
                            text: $password,
                            errorMessage: appState.authenticationFieldErrors.password
                        )
                    }

                    if let message = appState.authenticationErrorMessage {
                        Text(message)
                            .font(.fbCaption(.medium))
                            .foregroundStyle(FBColors.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FBPrimaryButton(
                        title: appState.isAuthenticationSubmitting ? "One sec" : (isSignUp ? "Create account" : "Sign in"),
                        systemImage: isSignUp ? "sparkles" : "arrow.right"
                    ) {
                        Task {
                            if isSignUp {
                                appState.updateLocalAvatar(selectedAvatar)
                                await appState.submitSignUp(name: name, phone: phone, email: email, password: password)
                            } else {
                                await appState.submitSignIn(phone: phone, password: password)
                            }
                        }
                    }
                    .disabled(appState.isAuthenticationSubmitting)
                    .opacity(appState.isAuthenticationSubmitting ? 0.72 : 1)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appState.authenticationErrorMessage = nil
                            appState.authenticationFieldErrors = AuthFieldErrors()
                            appState.authenticationMode = isSignUp ? .signIn : .signUp
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isSignUp ? "Already have an account?" : "New to Fitbites?")
                            Text(isSignUp ? "Sign in" : "Create one")
                                .font(.fbHeadline(.bold))
                        }
                        .font(.fbBody())
                        .foregroundStyle(FBColors.cookieOrange)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, FBSpacing.lg)
                .padding(.top, 84)
                .padding(.bottom, 42)
            }
        }
        .onAppear {
            selectedAvatar = appState.customerProfile.avatar
        }
        .onChange(of: selectedAvatar) { _, avatar in
            guard isSignUp else { return }
            appState.updateLocalAvatar(avatar)
        }
        .onChange(of: phone) { _, _ in
            appState.clearAuthenticationFieldError(.phone)
        }
        .onChange(of: password) { _, _ in
            appState.clearAuthenticationFieldError(.password)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let avatarData = Self.avatarPhotoData(from: data)
                else { return }

                selectedAvatar = LocalAvatar(
                    presetID: selectedAvatar.presetID,
                    customPhotoData: avatarData
                )
            }
        }
    }

    private static func avatarPhotoData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let targetSize = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let renderedImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        return renderedImage.jpegData(compressionQuality: 0.78)
    }
}

private struct AuthAvatarPicker: View {
    @Binding var avatar: LocalAvatar
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FBAvatarView(avatar: avatar, size: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose your avatar")
                        .font(.fbHeadline(.bold))
                        .foregroundStyle(FBColors.charcoal)

                    Text("Saved on this iPhone.")
                        .font(.fbCaption(.medium))
                        .foregroundStyle(FBColors.muted)
                }

                Spacer()

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FBColors.cookieOrange)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(FBColors.line.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Upload avatar photo")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LocalAvatarPreset.all) { preset in
                        AvatarPresetButton(
                            preset: preset,
                            isSelected: avatar.customPhotoData == nil && avatar.presetID == preset.id
                        ) {
                            avatar = LocalAvatar(presetID: preset.id, customPhotoData: nil)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.7), lineWidth: 1))
    }
}

private struct AvatarPresetButton: View {
    let preset: LocalAvatarPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                FBAvatarView(
                    avatar: LocalAvatar(presetID: preset.id, customPhotoData: nil),
                    size: 46
                )

                Text(preset.name)
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .foregroundStyle(isSelected ? FBColors.cookieOrange : FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 74)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white : Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? FBColors.cookieOrange : FBColors.line.opacity(0.5), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(preset.name) avatar")
    }
}

private struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    var keyboardType: UIKeyboardType = .default
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FBColors.cookieOrange)
                    .frame(width: 22)

                TextField(title, text: $text)
                    .font(.fbBody())
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, FBSpacing.md)
            .frame(height: 56)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(
                RoundedRectangle(cornerRadius: FBCorner.card)
                    .stroke(fieldBorderColor, lineWidth: errorMessage == nil ? 1 : 1.35)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.fbCaption(.medium))
                    .foregroundStyle(FBColors.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var fieldBorderColor: Color {
        errorMessage == nil ? FBColors.line.opacity(0.7) : FBColors.cookieOrange.opacity(0.7)
    }
}

private struct AuthSecureField: View {
    let title: String
    @Binding var text: String
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FBColors.cookieOrange)
                    .frame(width: 22)

                SecureField(title, text: $text)
                    .font(.fbBody())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, FBSpacing.md)
            .frame(height: 56)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(
                RoundedRectangle(cornerRadius: FBCorner.card)
                    .stroke(fieldBorderColor, lineWidth: errorMessage == nil ? 1 : 1.35)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.fbCaption(.medium))
                    .foregroundStyle(FBColors.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var fieldBorderColor: Color {
        errorMessage == nil ? FBColors.line.opacity(0.7) : FBColors.cookieOrange.opacity(0.7)
    }
}
