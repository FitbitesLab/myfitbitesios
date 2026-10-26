import SwiftUI

struct WidgetPresentation: Identifiable {
    let id = UUID()
    let route: WidgetRoute
}

extension AppState {
    func openWidgetURL(_ url: URL) {
        guard let route = WidgetRoute(url: url) else { return }
        pendingWidgetRoute = route
        consumePendingWidgetRoute()
    }

    func consumePendingWidgetRoute() {
        guard authenticationStatus == .authenticated, hasFinishedLaunchEntrance,
              let route = pendingWidgetRoute else { return }
        pendingWidgetRoute = nil
        // A cached widget belonging to a different login must not resolve an account-specific ID.
        let current = WidgetSnapshotBridge.shared.snapshot
        let safeRoute = route.sessionID == current.sessionID ? route : WidgetRoute(topic: route.topic)
        switch safeRoute.topic {
        case .reorder: selectedTab = .order
        case .lab: selectedTab = .progress
        case .cookies: selectedTab = .home
        case .stamps, .streak, .today: selectedTab = .home
        }
        widgetPresentation = WidgetPresentation(route: safeRoute)
    }
}

struct WidgetDestinationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let presentation: WidgetPresentation
    @State private var isLoading = true
    @State private var error: String?
    @State private var order: CustomerOrderSummary?
    @State private var products: [Int: StoreProduct] = [:]
    @State private var readyToReorder = false
    @State private var checkedAccount: Int?
    @State private var isArcadePresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView(widgetCopy("Checking the latest details…", "Đang kiểm tra thông tin mới nhất…"))
                    } else if let error {
                        ContentUnavailableView(widgetCopy("Please try again", "Vui lòng thử lại"), systemImage: "arrow.clockwise", description: Text(error))
                        Button(widgetCopy("Retry", "Thử lại")) { Task { await refresh() } }
                    } else {
                        destination
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle(presentation.route.topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(widgetCopy("Done", "Xong")) { dismiss() } } }
            .task { await refresh() }
            .fullScreenCover(isPresented: $isArcadePresented) { LabArcadeExperimentView() }
        }
    }

    @ViewBuilder private var destination: some View {
        let snapshot = WidgetSnapshotBridge.shared.snapshot
        switch presentation.route.topic {
        case .today: todayDestination(snapshot)
        case .streak:
            if let streak = snapshot.streak {
                Text("\(streak.value.count) " + widgetCopy("day order streak", "ngày đặt món liên tiếp"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(widgetCopy("Longest streak: ", "Chuỗi dài nhất: ") + "\(streak.value.longest)")
                if let next = streak.value.nextBonus {
                    Text(widgetCopy("\(next.days) consecutive days unlock a \(next.percent)% order XP bonus.", "\(next.days) ngày liên tiếp mở thưởng \(next.percent)% XP đặt món."))
                }
                Text(widgetCopy("Completed orders count once per day. Streak days currently follow the server’s UTC calendar.", "Đơn hoàn tất được tính một lần mỗi ngày. Chuỗi hiện theo múi giờ UTC của máy chủ."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else { unavailable }
        case .stamps, .cookies:
            if let loyalty = snapshot.loyalty?.value {
                Text("\(loyalty.stamps) / \(loyalty.target)").font(.system(.largeTitle, design: .rounded, weight: .bold))
                ProgressView(value: Double(loyalty.stamps), total: Double(loyalty.target))
                Text(widgetCopy("\(loyalty.rewards) free Fitbites rewards available", "Có \(loyalty.rewards) phần thưởng Fitbites miễn phí"))
                Button(widgetCopy("View my rewards", "Xem phần thưởng")) { appState.selectedTab = .rewards; dismiss() }
            } else { unavailable }
        case .reorder:
            if let order {
                ForEach(order.reorderItems) { item in
                    let product = products[item.productID]
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(item.quantity) × \(product?.name ?? widgetCopy("Unavailable item", "Món không khả dụng"))").font(.headline)
                        if let product {
                            Text(product.priceVND.formatted() + " ₫").foregroundStyle(.secondary)
                            ForEach(product.toppings.filter { item.toppingIDs.contains($0.toppingID) }) { topping in
                                Text(topping.name + " · " + topping.priceVND.formatted() + " ₫").font(.footnote)
                            }
                        }
                    }
                }
                Text(widgetCopy("Current prices and options are shown. Confirm your pickup or delivery details in the cart before checkout.", "Giá và tùy chọn hiện tại được hiển thị. Xác nhận nhận món hoặc giao hàng trong giỏ trước khi thanh toán."))
                    .font(.footnote).foregroundStyle(.secondary)
                if readyToReorder {
                    Button(appState.cart.itemCount > 0 ? widgetCopy("Replace cart and review", "Thay giỏ hàng và kiểm tra") : widgetCopy("Add to cart and review", "Thêm vào giỏ và kiểm tra")) {
                        guard checkedAccount == appState.currentCustomerID, appState.authenticationStatus == .authenticated else { return }
                        appState.cart.clear()
                        for item in order.reorderItems {
                            guard let product = products[item.productID] else { continue }
                            appState.cart.add(product, toppings: product.toppings.filter { item.toppingIDs.contains($0.toppingID) }, quantity: item.quantity)
                        }
                        appState.shouldOpenCartOnOrderTab = true
                        appState.selectedTab = .order
                        dismiss()
                    }.buttonStyle(.borderedProminent)
                } else {
                    Text(widgetCopy("Some items or options are no longer available. Please choose again from the menu.", "Một số món hoặc tùy chọn không còn khả dụng. Vui lòng chọn lại từ thực đơn."))
                }
            } else {
                ContentUnavailableView(widgetCopy("Choose something delicious", "Chọn món ngon nhé"), systemImage: "bag", description: Text(widgetCopy("This order is no longer available to reorder. Browse the current menu.", "Không thể đặt lại đơn này. Hãy xem thực đơn hiện tại.")))
                Button(widgetCopy("Browse menu", "Xem thực đơn")) { appState.selectedTab = .order; dismiss() }
            }
        case .lab:
            let access = TooLabAccessState(dashboard: appState.dashboardRepository.dashboard(), labXP: appState.tooLabProgress.totalLXP)
            if let id = presentation.route.itemID, let prototype = access.prototypePreviews.first(where: { $0.id == id }), access.canBuy(prototype) {
                ActiveFoodExperimentCard(access: access, prototype: prototype)
            } else {
                Text(access.isLabUnlocked ? widgetCopy("Your lab is ready", "Phòng thí nghiệm đã sẵn sàng") : widgetCopy("Too’s Lab opens at Level 5", "Too’s Lab mở ở Cấp 5")).font(.title2.bold())
                Button(widgetCopy("Open Too’s Lab", "Mở Too’s Lab")) { appState.selectedTab = .progress; dismiss() }
            }
        }
    }

    @ViewBuilder private func todayDestination(_ snapshot: WidgetSnapshot) -> some View {
        let id = presentation.route.itemID ?? ""
        if id == "member", let member = snapshot.member?.value {
            Text(widgetCopy("Level ", "Cấp ") + member.level.formatted()).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(member.tier).font(.title3.bold())
            ProgressView(value: member.progress)
            Text(member.isMaximumLevel ? widgetCopy("Maximum level reached", "Đã đạt cấp cao nhất") : "\(member.levelXP.formatted()) / \(member.levelTarget.formatted()) XP")
        } else if id == "arcade" {
            Text("My Arcade").font(.title.bold())
            if let arcade = snapshot.arcade?.value, arcade.enabled {
                Text(widgetCopy("\(arcade.credits) credits available", "Còn \(arcade.credits) lượt chơi"))
                Button(widgetCopy("Explore games", "Khám phá trò chơi")) { isArcadePresented = true }
            } else { unavailable }
        } else if id.hasPrefix("lab-") {
            let access = TooLabAccessState(dashboard: appState.dashboardRepository.dashboard(), labXP: appState.tooLabProgress.totalLXP)
            let itemID = String(id.dropFirst(4))
            if let prototype = access.prototypePreviews.first(where: { $0.id == itemID }), access.canBuy(prototype) {
                ActiveFoodExperimentCard(access: access, prototype: prototype)
            } else {
                Text(widgetCopy("Check your current Lab access", "Kiểm tra quyền truy cập Lab hiện tại")).font(.headline)
                Button(widgetCopy("Open Too’s Lab", "Mở Too’s Lab")) { appState.selectedTab = .progress; dismiss() }
            }
        } else if id.hasPrefix("recipe-"), let itemID = Int(id.dropFirst(7)), let product = products[itemID], product.isAvailable {
            Text(product.name).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(product.description)
            Button(widgetCopy("View recipe", "Xem món")) {
                guard checkedAccount == appState.currentCustomerID else { return }
                appState.pendingStoreProductID = product.id
                appState.selectedTab = .order
                dismiss()
            }
        } else { unavailable }
    }

    private var unavailable: some View {
        Text(widgetCopy("This information is unavailable. Open the app again to refresh.", "Chưa có thông tin. Mở lại ứng dụng để cập nhật."))
    }

    @MainActor private func refresh() async {
        isLoading = true; error = nil; readyToReorder = false
        defer { isLoading = false }
        guard let client = appState.customerAPIClient, appState.authenticationStatus == .authenticated else { return }
        let account = appState.currentCustomerID
        do {
            let payload = try await client.dashboard()
            guard account == appState.currentCustomerID, payload.member?.id == account else { dismiss(); return }
            (appState.dashboardRepository as? CustomerV2DashboardPayloadCaching)?.applyDashboardPayload(payload)
            (appState.rewardsRepository as? CustomerV2DashboardPayloadCaching)?.applyDashboardPayload(payload)
            switch presentation.route.topic {
            case .today:
                let item = presentation.route.itemID ?? ""
                if item.hasPrefix("lab-") {
                    let lab = try await client.tooLabSummary()
                    guard account == appState.currentCustomerID else { dismiss(); return }
                    appState.tooLabProgress = CustomerV2Mapper.tooLabProgress(from: lab.tooLab)
                } else if item == "arcade" {
                    _ = try await client.arcadeSummary()
                    guard account == appState.currentCustomerID else { dismiss(); return }
                } else if item.hasPrefix("recipe-") {
                    let fresh = try await client.store()
                    guard account == appState.currentCustomerID else { dismiss(); return }
                    guard let catalog = CustomerV2Mapper.catalog(from: fresh, fallback: LocalCatalogRepository().catalog()) else { throw URLError(.cannotParseResponse) }
                    if let repository = appState.catalogRepository as? CustomerDataRefreshing { await repository.refresh() }
                    guard account == appState.currentCustomerID else { dismiss(); return }
                    products = Dictionary(catalog.products.map { ($0.inventoryItemID, $0) }, uniquingKeysWith: { a, _ in a })
                }
                checkedAccount = account
            case .cookies, .stamps:
                _ = try await client.rewardsSummary()
            case .lab:
                let lab = try await client.tooLabSummary()
                guard account == appState.currentCustomerID else { dismiss(); return }
                appState.tooLabProgress = CustomerV2Mapper.tooLabProgress(from: lab.tooLab)
            case .reorder:
                let fresh = try await client.store()
                guard account == appState.currentCustomerID else { dismiss(); return }
                guard let catalog = CustomerV2Mapper.catalog(from: fresh, fallback: LocalCatalogRepository().catalog()) else { throw URLError(.cannotParseResponse) }
                // Refresh the app's catalog too; the existing cart flow uses its current product models.
                if let repository = appState.catalogRepository as? CustomerDataRefreshing { await repository.refresh() }
                products = Dictionary(catalog.products.map { ($0.inventoryItemID, $0) }, uniquingKeysWith: { a, _ in a })
                let id = presentation.route.itemID.flatMap(Int.init)
                order = appState.dashboardRepository.dashboard().pastOrders.first { $0.id == id && $0.status == "completed" }
                readyToReorder = order.map { order in
                    !order.reorderItems.isEmpty && order.reorderItems.allSatisfy { item in
                        guard let product = products[item.productID], product.isAvailable else { return false }
                        return Set(item.toppingIDs).isSubset(of: Set(product.toppings.map(\.toppingID)))
                    }
                } ?? false
                checkedAccount = account
            default: break
            }
        } catch { self.error = widgetCopy("Couldn’t verify the current account details. Nothing has been ordered.", "Chưa xác minh được thông tin hiện tại. Chưa có đơn nào được đặt.") }
    }
}
