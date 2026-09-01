import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var heroScene: DashboardHeroScene = DashboardHeroResolver().resolve()
    #if DEBUG
    @State private var debugHeroSceneOverride: DashboardHeroScene?
    #endif
    @AppStorage(RightNowPersistenceKey.lastAcknowledgedLabUnlockID) private var lastAcknowledgedLabUnlockID = ""
    @AppStorage(RightNowPersistenceKey.lastAcknowledgedStreakMilestone) private var lastAcknowledgedStreakMilestone = 0
    @AppStorage(RightNowPersistenceKey.lastStreakSurpriseRollKey) private var lastStreakSurpriseRollKey = ""
    @State private var streakSurpriseDays: Int?
    @State private var pendingFreeFitbitesAnnouncementAcknowledgements: Set<String> = []
    #if DEBUG
    @AppStorage(RightNowPersistenceKey.debugOverride) private var rightNowDebugOverrideRaw = RightNowDebugOverride.automatic.rawValue
    #endif
    private let heroResolver = DashboardHeroResolver()
    private let rightNowResolver = RightNowCardResolver()

    private var dashboard: CustomerDashboard {
        appState.dashboardRepository.dashboard()
    }

    private var catalog: StoreCatalog {
        appState.catalogRepository.catalog()
    }

    private var rewards: RewardsProgress {
        appState.rewardsRepository.rewards()
    }

    private var nextAchievement: Achievement? {
        rewards.achievements.first { !$0.isUnlocked } ?? rewards.achievements.first
    }

    private var rightNowState: RightNowCardState {
        #if DEBUG
        let override = RightNowDebugOverride(rawValue: rightNowDebugOverrideRaw) ?? .automatic
        if override != .automatic {
            return debugRightNowState(for: override)
        }
        #endif

        return rightNowResolver.resolve(context: rightNowContext)
    }

    private var rightNowContext: RightNowContext {
        RightNowContext(
            dashboard: dashboard,
            rewards: rewards,
            catalog: catalog,
            activeOrder: dashboard.activeOrder,
            labUnlocks: labUnlocks,
            lastAcknowledgedLabUnlockID: lastAcknowledgedLabUnlockID.isEmpty ? nil : lastAcknowledgedLabUnlockID,
            daysSinceLastCompletedOrder: dashboard.daysSinceLastCompletedOrder,
            completedOrderProductIDs: dashboard.completedOrderProductIDs,
            repeatedOrderCounts: dashboard.repeatedOrderCounts,
            lastAcknowledgedStreakMilestone: lastAcknowledgedStreakMilestone,
            streakSurpriseDays: streakSurpriseDays
        )
    }

    private var labUnlocks: [RightNowLabUnlock] {
        [
            RightNowLabUnlock(
                id: "lab-assistant",
                level: 5,
                title: "TOO'S LAB",
                subtitle: "LXP and clearance begin here."
            )
        ]
    }

    private var latestReorderableOrder: CustomerOrderSummary? {
        dashboard.pastOrders.first { order in
            order.status.lowercased() == "completed" && !order.reorderItems.isEmpty
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: FBSpacing.lg) {
                    heroHeader(screenWidth: proxy.size.width)

                    content
                }
                .padding(.bottom, 24)
            }
            .background(Color.white.ignoresSafeArea())
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                rollStreakSurpriseIfNeeded()
                await refreshHeroScene()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                rollStreakSurpriseIfNeeded()
                Task {
                    await appState.refreshDashboardAndRewards()
                    await refreshHeroScene()
                }
            }
            .onChange(of: appState.dashboardHeroWeatherCondition) { _, _ in
                updateHeroScene()
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: FBSpacing.lg) {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                FBXPProgress(
                    level: dashboard.level,
                    xp: dashboard.xp,
                    xpToNext: dashboard.xpToNext,
                    targetXP: dashboard.levelTarget,
                    headline: dashboard.name,
                    avatar: appState.customerProfile.avatar
                )
                .offset(y: -48)
                .padding(.bottom, -48)
                .zIndex(1)

                rightNowSection

                HomeLoyaltyStampCard(completed: rewards.loyaltyStamps, total: rewards.loyaltyTarget)

                HomeAchievementsCard(achievement: nextAchievement)

                TooLabHomeCard(level: dashboard.level) {
                    appState.selectedTab = .progress
                }

                if let reorderOrder = latestReorderableOrder {
                    ReorderCard(order: reorderOrder, catalog: appState.catalogRepository.catalog()) {
                        appState.reorder(reorderOrder)
                    }
                }

                FBPrimaryButton(title: "Order Fitbites", systemImage: "bag") {
                    appState.selectedTab = .order
                }
            }
            .padding(.horizontal, FBSpacing.md)
        }
    }

    private func heroHeader(screenWidth: CGFloat) -> some View {
        heroIntro(screenWidth: screenWidth)
        .frame(width: screenWidth, height: 628)
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    private func heroIntro(screenWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(heroScene.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: screenWidth, height: 628)
                .clipped()
                .accessibilityLabel("Too and Tiel in the Fitbites kitchen")
                .id(heroScene.assetName)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.36), value: heroScene)
                #if DEBUG
                .onLongPressGesture {
                    cycleDebugHeroScene()
                }
                #endif

            LinearGradient(
                colors: [
                    FBColors.ivory.opacity(0.98),
                    FBColors.ivory.opacity(0.64),
                    FBColors.ivory.opacity(0.08),
                    FBColors.ivory.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 260)

            VStack(alignment: .leading, spacing: 8) {
                topChrome
                HeroMicrocopySlider(dashboard: dashboard)
            }
            .padding(.horizontal, FBSpacing.md)
            .padding(.top, 62)

        }
    }

    private func refreshHeroScene() async {
        await appState.refreshDashboardHeroWeather()
        updateHeroScene()
    }

    private func updateHeroScene() {
        #if DEBUG
        if let debugHeroSceneOverride {
            guard heroScene != debugHeroSceneOverride else { return }

            withAnimation(.easeInOut(duration: 0.36)) {
                heroScene = debugHeroSceneOverride
            }
            return
        }
        #endif

        let nextScene = heroResolver.resolve(weatherCondition: appState.dashboardHeroWeatherCondition)
        guard heroScene != nextScene else { return }

        withAnimation(.easeInOut(duration: 0.36)) {
            heroScene = nextScene
        }
    }

    #if DEBUG
    private func cycleDebugHeroScene() {
        let nextOverride: DashboardHeroScene?

        if
            let debugHeroSceneOverride,
            let currentIndex = DashboardHeroScene.allCases.firstIndex(of: debugHeroSceneOverride)
        {
            let nextIndex = DashboardHeroScene.allCases.index(after: currentIndex)
            nextOverride = nextIndex == DashboardHeroScene.allCases.endIndex ? nil : DashboardHeroScene.allCases[nextIndex]
        } else {
            nextOverride = DashboardHeroScene.allCases.first
        }

        debugHeroSceneOverride = nextOverride
        updateHeroScene()
    }
    #endif

    @ViewBuilder
    private var rightNowSection: some View {
        if rightNowState == .none {
            #if DEBUG
            RightNowDebugOverrideMenu(selectionRaw: $rightNowDebugOverrideRaw)
                .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
        } else {
            RightNowCard(state: rightNowState) {
                handleRightNowAction(rightNowState)
            }
            .onAppear {
                acknowledgeFreeFitbitesAnnouncementIfNeeded(for: rightNowState)
            }
            .overlay(alignment: .topTrailing) {
                #if DEBUG
                RightNowDebugOverrideMenu(selectionRaw: $rightNowDebugOverrideRaw)
                    .padding(10)
                #endif
            }
            .id(rightNowState.id)
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
    }

    private func handleRightNowAction(_ state: RightNowCardState) {
        switch state {
        case .activeOrder:
            break
        case .labUnlock(let unlock):
            lastAcknowledgedLabUnlockID = unlock.id
            appState.selectedTab = .progress
        case .rewardReady:
            appState.selectedTab = .rewards
        case .nearReward, .welcomeBack:
            appState.selectedTab = .order
        case .usualOrder(let usual):
            appState.pendingStoreProductID = usual.product.id
            appState.selectedTab = .order
        case .streak(let streak):
            lastAcknowledgedStreakMilestone = max(lastAcknowledgedStreakMilestone, streak.days)
            appState.selectedTab = .progress
        case .discovery(let discovery):
            appState.pendingStoreProductID = discovery.product.id
            appState.selectedTab = .order
        case .none:
            appState.selectedTab = .order
        }
    }

    private func acknowledgeFreeFitbitesAnnouncementIfNeeded(for state: RightNowCardState) {
        guard
            case .rewardReady(let reward) = state,
            let rewardID = reward.unannouncedRewardID,
            !pendingFreeFitbitesAnnouncementAcknowledgements.contains(rewardID),
            let client = appState.customerAPIClient
        else { return }

        pendingFreeFitbitesAnnouncementAcknowledgements.insert(rewardID)

        Task {
            try? await client.acknowledgeFreeFitbitesAnnouncement(rewardID: rewardID)
            await appState.refreshDashboardAndRewards()

            await MainActor.run {
                _ = pendingFreeFitbitesAnnouncementAcknowledgements.remove(rewardID)
            }
        }
    }

    private func rollStreakSurpriseIfNeeded(date: Date = Date()) {
        let streakDays = dashboard.currentStreakDays
        guard streakDays > 0 else {
            streakSurpriseDays = nil
            return
        }

        let rollKey = "\(Self.streakSurpriseDayFormatter.string(from: date)):\(streakDays)"
        guard lastStreakSurpriseRollKey != rollKey else { return }

        lastStreakSurpriseRollKey = rollKey
        streakSurpriseDays = shouldPlayStreakSurprise(for: streakDays) ? streakDays : nil
    }

    private func shouldPlayStreakSurprise(for streakDays: Int) -> Bool {
        switch streakDays {
        case 1:
            Bool.random(probability: 0.3)
        case 2...4:
            Bool.random(probability: 0.25)
        case 5:
            true
        case 10, 15:
            Bool.random(probability: 0.4)
        default:
            streakDays > 15 && streakDays.isMultiple(of: 5) && Bool.random(probability: 0.18)
        }
    }

    private static let streakSurpriseDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    #if DEBUG
    private func debugRightNowState(for override: RightNowDebugOverride) -> RightNowCardState {
        let fallbackProduct = catalog.products.first ?? dashboard.usualProduct

        switch override {
        case .automatic:
            return rightNowResolver.resolve(context: rightNowContext)
        case .activeOrder:
            return .activeOrder(RightNowActiveOrder(productName: "Tiram'oats", orderNumber: "#1842", status: .preparing, estimateText: "~8 min"))
        case .labUnlock:
            return .labUnlock(RightNowLabUnlock(id: "debug-lab", level: 8, title: "Chocolate Mulberry", subtitle: "Experiment #008 unlocked"))
        case .rewardReady:
            return .rewardReady(RightNowRewardReady(availableCount: 1, unannouncedRewardID: nil))
        case .nearReward:
            return .nearReward(RightNowNearReward(stampsRemaining: 1))
        case .welcomeBack:
            return .welcomeBack(RightNowWelcomeBack(daysSinceLastOrder: 14))
        case .usualOrder:
            return .usualOrder(RightNowUsualOrder(product: dashboard.usualProduct, orderCount: 3))
        case .streak:
            return .streak(RightNowStreak(days: 5))
        case .discovery:
            return .discovery(RightNowDiscovery(product: fallbackProduct))
        case .none:
            return .none
        }
    }
    #endif

    private var topChrome: some View {
        HStack(alignment: .top) {
            Image("FitbitesLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 142, height: 38, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Fitbites")

            Spacer()

            notificationButton
        }
    }

    private var notificationButton: some View {
        Button {} label: {
            Image(systemName: "bell")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FBColors.charcoal)
                .frame(width: 42, height: 42)
                .background(FBColors.surface.opacity(0.92), in: Circle())
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(FBColors.cookieOrange)
                        .frame(width: 8, height: 8)
                        .offset(x: -9, y: 10)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
    }

    private var usual: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your usual")
                .font(.fbHeadline(.bold))
                .foregroundStyle(FBColors.charcoal)

            Button {
                appState.selectedTab = .order
            } label: {
                HStack(spacing: 12) {
                    ProductImageTile(imageName: dashboard.usualProduct.imageName, imageURL: dashboard.usualProduct.imageURL)
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(dashboard.usualProduct.name)
                            .font(.fbHeadline(.semibold))
                            .foregroundStyle(FBColors.charcoal)
                        Text("Oats")
                            .font(.fbCaption())
                            .foregroundStyle(FBColors.muted)
                        Text(dashboard.usualProduct.protein)
                            .font(.fbCaption(.semibold))
                            .foregroundStyle(FBColors.cookieOrange)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FBColors.charcoal)
                }
                .padding(10)
                .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Chocolate Mulberry")
        }
    }
}

private struct RightNowCard: View {
    let state: RightNowCardState
    let action: () -> Void

    private var content: RightNowCardContent {
        switch state {
        case .activeOrder(let order):
            switch order.status {
            case .preparing:
                RightNowCardContent(
                    eyebrowIcon: "alarm",
                    headline: "Too is cooking",
                    accentHeadline: true,
                    detailLines: [order.productName, "Order \(order.orderNumber)"],
                    pillText: ["Preparing", order.estimateText].compactMap { $0 }.joined(separator: "  -  "),
                    ctaSymbol: "arrow.right",
                    artworkSymbol: "fork.knife",
                    artworkImageName: "RightNowTooCooking",
                    artworkTint: FBColors.cookieOrange
                )
            case .ready:
                RightNowCardContent(
                    eyebrowIcon: "heart.fill",
                    headline: "It's ready",
                    accentHeadline: true,
                    detailLines: ["Your Fitbites is waiting.", order.productName],
                    pillText: "View order",
                    ctaSymbol: "arrow.right",
                    artworkSymbol: "checkmark.seal.fill",
                    artworkTint: FBColors.tielYellow
                )
            case .outForDelivery:
                RightNowCardContent(
                    eyebrowIcon: "scooter",
                    headline: "Order on the way",
                    accentHeadline: false,
                    detailLines: [order.productName, order.estimateText ?? "On the road"],
                    pillText: "Track order",
                    ctaSymbol: "arrow.right",
                    artworkSymbol: "takeoutbag.and.cup.and.straw.fill",
                    artworkTint: FBColors.cookieOrange
                )
            }
        case .labUnlock(let unlock):
                RightNowCardContent(
                    eyebrowIcon: "flask",
                    headline: "Lab unlocked",
                    accentHeadline: false,
                    detailLines: [unlock.title, unlock.subtitle],
                    pillText: "Enter Too's Lab",
                    ctaSymbol: "arrow.right",
                    artworkSymbol: "testtube.2",
                    artworkImageName: "RightNowLabUnlocked",
                    artworkTint: Color.purple
                )
        case .rewardReady(let reward):
            RightNowCardContent(
                eyebrowIcon: "gift.fill",
                headline: reward.isNewUnlock ? "FREE REWARD UNLOCKED" : "Reward ready",
                accentHeadline: false,
                detailLines: [reward.isNewUnlock ? "Choose a Daily or standard coffee at Fitbites." : "Your free reward is ready."],
                pillText: "Use reward",
                ctaSymbol: "arrow.right",
                artworkSymbol: "gift.fill",
                artworkImageName: "RightNowRewardReady",
                artworkTint: FBColors.tielYellow
            )
        case .nearReward:
            RightNowCardContent(
                eyebrowIcon: "seal.fill",
                headline: "One more",
                accentHeadline: false,
                detailLines: ["One more stamp until your free reward."],
                pillText: "Order",
                ctaSymbol: "arrow.right",
                artworkSymbol: "heart.circle.fill",
                artworkImageName: "RightNowOneMoreStamp",
                artworkTint: FBColors.cookieOrange
            )
        case .welcomeBack(let welcomeBack):
            RightNowCardContent(
                eyebrowIcon: "sparkles",
                headline: "Too missed you",
                accentHeadline: false,
                detailLines: ["Tiel claims she didn't.", "\(welcomeBack.daysSinceLastOrder) days since your last order"],
                pillText: "See what's cooking",
                ctaSymbol: "arrow.right",
                artworkSymbol: "sparkles",
                artworkImageName: "RightNowTooMissedYou",
                artworkTint: FBColors.cookieOrange
            )
        case .usualOrder(let usual):
            RightNowCardContent(
                eyebrowIcon: "clock.fill",
                headline: "Your usual",
                accentHeadline: false,
                detailLines: [usual.product.name, "Ordered \(usual.orderCount)x recently"],
                pillText: "Order again",
                ctaSymbol: "arrow.right",
                artworkSymbol: "takeoutbag.and.cup.and.straw.fill",
                artworkImageName: "RightNowYourUsual",
                artworkTint: FBColors.cookieOrange
            )
        case .streak(let streak):
            RightNowCardContent(
                eyebrowIcon: "flame.fill",
                headline: "\(streak.days) days strong",
                accentHeadline: true,
                detailLines: streakDetailLines(for: streak.days),
                pillText: "View journey",
                ctaSymbol: "arrow.right",
                artworkSymbol: "flame.fill",
                artworkImageName: (1...5).contains(streak.days) ? "RightNowEarlyStreak" : nil,
                artworkTint: FBColors.caramel
            )
        case .discovery(let discovery):
            RightNowCardContent(
                eyebrowIcon: "sparkle.magnifyingglass",
                headline: "Try new",
                accentHeadline: false,
                detailLines: ["You've never tried", discovery.product.name],
                pillText: "Discover",
                ctaSymbol: "arrow.right",
                artworkSymbol: "sparkles",
                artworkImageName: "RightNowDiscovery",
                artworkTint: FBColors.cookieOrange
            )
        case .none:
            RightNowCardContent(
                eyebrowIcon: "sparkles",
                headline: "Right now",
                accentHeadline: false,
                detailLines: ["Everything is quiet."],
                pillText: "Order Fitbites",
                ctaSymbol: "arrow.right",
                artworkSymbol: "takeoutbag.and.cup.and.straw.fill",
                artworkTint: FBColors.cookieOrange
            )
        }
    }

    private var headlineText: String {
        content.headline
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func streakDetailLines(for days: Int) -> [String] {
        if days == 5 {
            return ["Max streak boost unlocked.", "Keep the fire going."]
        }

        return ["Too is impressed.", "Tiel is checking the numbers."]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HomeCardEyebrow(icon: content.eyebrowIcon, title: "RIGHT NOW", tint: FBColors.cookieOrange)

                    Text(headlineText.uppercased())
                        .font(.custom("AvenirNext-DemiBold", size: 18))
                        .foregroundStyle(content.accentHeadline ? FBColors.caramel : FBColors.charcoal)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(content.detailLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.custom(index == 0 ? "AvenirNext-Medium" : "AvenirNext-Regular", size: 15))
                                .tracking(0.2)
                                .foregroundStyle(index == 0 ? FBColors.charcoal.opacity(0.92) : FBColors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }

                    Text(content.pillText.uppercased())
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .tracking(0.9)
                        .foregroundStyle(FBColors.caramel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(FBColors.card, in: Capsule())
                        .overlay(Capsule().stroke(FBColors.line.opacity(0.7)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RightNowArtwork(content: content)
                    .frame(width: 116, height: 108)

                Image(systemName: content.ctaSymbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(FBColors.charcoal)
                    .frame(width: 38, height: 38)
                    .background(FBColors.surface, in: Circle())
                    .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
            }
            .padding(FBSpacing.md)
            .frame(minHeight: 144)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Right now, \(headlineText)")
    }
}

private struct RightNowCardContent {
    let eyebrowIcon: String
    let headline: String
    let accentHeadline: Bool
    let detailLines: [String]
    let pillText: String
    let ctaSymbol: String
    let artworkSymbol: String
    var artworkImageName: String?
    let artworkTint: Color
}

private struct HomeCardEyebrow: View {
    let icon: String
    let title: String
    var tint: Color = FBColors.cookieOrange

    private var iconSize: CGFloat {
        switch icon {
        case "birthday.cake.fill":
            10.5
        default:
            12
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .tracking(1.7)
                .foregroundStyle(FBColors.charcoal)
        }
        .frame(height: 18, alignment: .center)
        .accessibilityHidden(true)
    }
}

private struct RightNowArtwork: View {
    let content: RightNowCardContent

    private var imageSize: CGFloat {
        switch content.artworkImageName {
        case "RightNowTooCooking":
            143
        case "RightNowOneMoreStamp":
            164
        case "RightNowRewardReady":
            148
        case "RightNowTooMissedYou":
            154
        case "RightNowYourUsual":
            150
        case "RightNowEarlyStreak":
            148
        case "RightNowDiscovery":
            152
        default:
            130
        }
    }

    private var imageOffset: CGSize {
        switch content.artworkImageName {
        case "RightNowOneMoreStamp":
            CGSize(width: 16, height: 0)
        case "RightNowRewardReady":
            CGSize(width: 10, height: 0)
        case "RightNowTooMissedYou":
            CGSize(width: 14, height: 0)
        case "RightNowYourUsual":
            CGSize(width: 12, height: 0)
        case "RightNowEarlyStreak":
            CGSize(width: 12, height: 0)
        case "RightNowDiscovery":
            CGSize(width: 12, height: 0)
        default:
            CGSize(width: 4, height: 0)
        }
    }

    var body: some View {
        if let artworkImageName = content.artworkImageName {
            Image(artworkImageName)
                .resizable()
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
                .offset(imageOffset)
                .opacity(0.8)
                .accessibilityHidden(true)
        } else {
            ZStack {
                Circle()
                    .fill(content.artworkTint.opacity(0.14))
                    .frame(width: 92, height: 92)

                Image(systemName: content.artworkSymbol)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(content.artworkTint)
            }
            .accessibilityHidden(true)
        }
    }
}

private extension Bool {
    static func random(probability: Double) -> Bool {
        Double.random(in: 0..<1) < probability
    }
}

#if DEBUG
private struct RightNowDebugOverrideMenu: View {
    @Binding var selectionRaw: String

    var body: some View {
        Menu {
            ForEach(RightNowDebugOverride.allCases) { override in
                Button(override.title) {
                    selectionRaw = override.rawValue
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FBColors.charcoal)
                .frame(width: 30, height: 30)
                .background(FBColors.surface.opacity(0.94), in: Circle())
                .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Debug Right Now state")
    }
}
#endif

struct CharacterBubble: View {
    let name: String
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.86))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)

            Text(name)
                .font(.fbHeadline(.black))
                .foregroundStyle(FBColors.charcoal)
        }
        .accessibilityLabel(name)
    }
}

private struct HeroMicrocopySlider: View {
    let dashboard: CustomerDashboard
    @State private var activeIndex = 0
    private let timer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 18 {
            return "Good evening,"
        }
        if hour >= 12 {
            return "Good afternoon,"
        }
        return "Good morning,"
    }

    private var messages: [String] {
        [
            "\(greeting) \(dashboard.name)!",
            "MyFitbites Member since \(dashboard.memberSince)",
            "Tier : \(dashboard.tierName)",
            "Level \(dashboard.level)/\(MyFitbitesLevelDisplay.bandMax(for: dashboard.level))"
        ]
    }

    var body: some View {
        Text(messages[activeIndex])
            .font(.custom("AvenirNext-Regular", size: 12))
            .tracking(1.7)
            .textCase(.uppercase)
            .foregroundStyle(FBColors.charcoal)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .id(activeIndex)
            .transition(.opacity)
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: FBColors.ivory.opacity(0.78), radius: 7, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(messages[activeIndex])
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.46)) {
                activeIndex = (activeIndex + 1) % messages.count
            }
        }
    }
}

private struct HomeLoyaltyStampCard: View {
    let completed: Int
    let total: Int

    private var remaining: Int {
        max(0, total - completed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HomeCardEyebrow(icon: "birthday.cake.fill", title: "LOYALTY CARD")

                Spacer()

                Text("\(completed)/\(total)")
                    .font(.fbCaption(.semibold))
                    .foregroundStyle(FBColors.muted)
            }

            HStack(spacing: 0) {
                ForEach(1...total, id: \.self) { index in
                    HomeLoyaltyStamp(isComplete: index <= completed)

                    if index < total {
                        Spacer(minLength: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: FBSpacing.sm) {
                (
                    Text("\(remaining) MORE TO GET ")
                        .foregroundStyle(FBColors.muted)
                    + Text("1 FREE REWARD!")
                        .foregroundStyle(FBColors.caramel)
                )
                .font(.custom("AvenirNext-DemiBold", size: 13))
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                Spacer(minLength: FBSpacing.sm)

                Image(systemName: "gift.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(FBColors.cookieOrange.opacity(0.18))
                    .frame(width: 54, height: 44)
                .accessibilityHidden(true)
            }
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loyalty card, \(completed) of \(total) stamps complete, \(remaining) more to get 1 free reward")
    }
}

private struct HomeLoyaltyStamp: View {
    let isComplete: Bool

    var body: some View {
        Image("BCookieStamp")
            .renderingMode(isComplete ? .original : .template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(FBColors.line.opacity(0.72))
            .opacity(isComplete ? 1 : 0.32)
            .frame(width: 30, height: 34)
            .frame(width: 32, height: 38)
    }
}

private struct HomeAchievementsCard: View {
    let achievement: Achievement?

    private var title: String {
        achievement?.title ?? "Keep ordering"
    }

    private var subtitle: String {
        if let achievement {
            return achievement.isUnlocked ? "All current achievements unlocked." : achievement.subtitle
        }

        return "Your next achievement will appear here."
    }

    private var progressText: String {
        guard let achievement else { return "0/1" }

        if let progress = achievement.progress, let target = achievement.target {
            return "\(progress)/\(target)"
        }

        return achievement.status.uppercased()
    }

    var body: some View {
        NavigationLink {
            AccountAchievementsView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HomeCardEyebrow(icon: "trophy.fill", title: "ACHIEVEMENTS")

                    Spacer()

                    Text(progressText)
                        .font(.fbCaption(.semibold))
                        .foregroundStyle(FBColors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                HStack(alignment: .center, spacing: FBSpacing.md) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next achievement to unlock")
                            .font(.custom("AvenirNext-DemiBold", size: 13))
                            .tracking(0.8)
                            .foregroundStyle(FBColors.caramel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(title)
                            .font(.custom("AvenirNext-DemiBold", size: 16))
                            .foregroundStyle(FBColors.charcoal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(subtitle)
                            .font(.custom("AvenirNext-Regular", size: 12))
                            .tracking(0.45)
                            .foregroundStyle(FBColors.muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }

                    Spacer(minLength: FBSpacing.sm)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FBColors.charcoal)
                        .frame(width: 36, height: 36)
                        .background(FBColors.surface.opacity(0.92), in: Circle())
                        .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
                }
            }
            .padding(FBSpacing.md)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievements, next achievement to unlock, \(title)")
    }
}

private struct TooLabHomeCard: View {
    let level: Int
    let action: () -> Void

    private let unlockLevel = 5

    private var tint: Color {
        level >= unlockLevel ? Color.purple : FBColors.cookieOrange
    }

    private var progress: Double {
        min(1, max(0, Double(level) / Double(unlockLevel)))
    }

    private var progressText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    private var isUnlocked: Bool {
        level >= unlockLevel
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image("TooLabHomeCard")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 138, height: 156)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: FBCorner.card,
                            bottomLeadingRadius: FBCorner.card,
                            bottomTrailingRadius: 10,
                            topTrailingRadius: 0
                        )
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    HomeCardEyebrow(icon: "flask", title: "TOO'S LAB", tint: tint.opacity(0.78))

                    Text(isUnlocked ? "LAB UNLOCKED" : "NEXT UNLOCK")
                        .font(.custom("AvenirNext-DemiBold", size: 19))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isUnlocked ? "LXP CLEARANCE" : "LEVEL 5 REQUIRED")
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                            .tracking(1.05)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(isUnlocked ? "Earn clearance inside Too's Lab." : "Unlock experiments at Level 5.")
                            .font(.custom("AvenirNext-Regular", size: 13))
                            .tracking(1.05)
                            .foregroundStyle(FBColors.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    HStack(spacing: 10) {
                        ProgressView(value: progress)
                            .tint(tint)
                            .frame(maxWidth: 128)

                        Text(progressText)
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                            .foregroundStyle(FBColors.charcoal)
                    }

                    Text(isUnlocked ? "CLEARANCE RUNS ON LXP" : "UNLOCKS AT LEVEL \(unlockLevel)")
                        .font(.custom("AvenirNext-Regular", size: 10))
                        .tracking(1.2)
                        .foregroundStyle(FBColors.muted)
                        .lineLimit(1)
                }
                .padding(.top, FBSpacing.md)
                .padding(.bottom, FBSpacing.md)
                .padding(.leading, FBSpacing.md)
                .padding(.trailing, FBSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FBColors.charcoal)
                    .frame(width: 36, height: 36)
                    .background(FBColors.surface.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
                    .padding(.trailing, FBSpacing.md)
            }
            .frame(height: 156)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUnlocked ? "Too's Lab unlocked, clearance runs on LXP" : "Too's Lab, \(progressText) progress, unlocks at level \(unlockLevel)")
    }
}

private struct ReorderCard: View {
    let order: CustomerOrderSummary
    let catalog: StoreCatalog
    let action: () -> Void

    private var firstProduct: StoreProduct? {
        guard let firstItem = order.reorderItems.first else { return nil }
        return catalog.products.first { $0.inventoryItemID == firstItem.productID }
    }

    private var title: String {
        if order.reorderItems.count == 1, let firstProduct {
            return firstProduct.name
        }

        return order.items
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let firstProduct {
                    ProductImageTile(imageName: firstProduct.imageName, imageURL: firstProduct.imageURL)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HomeCardEyebrow(icon: "bag.fill", title: "REORDER")

                    Text("Previous order")
                        .font(.custom("AvenirNext-Regular", size: 11))
                        .tracking(1.25)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.muted)

                    Text(title)
                        .font(.fbHeadline(.semibold))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 10)

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FBColors.charcoal)
                    .frame(width: 34, height: 34)
                    .background(FBColors.surface, in: Circle())
                    .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
            }
            .padding(FBSpacing.md)
            .frame(height: 96)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reorder previous order, \(title)")
    }
}
