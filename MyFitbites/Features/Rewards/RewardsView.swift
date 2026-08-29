import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct RewardsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var animatedXPProgress = 0.0
    @State private var selectedFreeFitbitesReward: FreeFitbitesReward?
    @State private var redemptionSession: FreeFitbitesRedemptionSession?
    @State private var rewardErrorMessage: String?
    @State private var isCreatingRedemptionSession = false
    @State private var pollingTask: Task<Void, Never>?

    private var rewards: RewardsProgress {
        appState.rewardsRepository.rewards()
    }

    private var dashboard: CustomerDashboard {
        appState.dashboardRepository.dashboard()
    }

    private var xpProgress: Double {
        let earned = max(0, rewards.levelTarget - rewards.xpToNext)
        return min(1, max(0, Double(earned) / Double(max(1, rewards.levelTarget))))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                rewardsHero

                achievementsMiniatureWidget

                loyaltyCard

                freeFitbitesRewardCard

                ricoStoreCard
            }
            .padding(FBSpacing.md)
            .padding(.bottom, FBSpacing.xl)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Rewards")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            animatedXPProgress = 0
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                animatedXPProgress = xpProgress
            }
        }
        .sheet(item: $selectedFreeFitbitesReward) { reward in
            FreeFitbitesRedemptionSheet(
                reward: reward,
                session: redemptionSession,
                errorMessage: rewardErrorMessage,
                isCreatingSession: isCreatingRedemptionSession,
                onShowQR: { Task { await createRedemptionSession(for: reward) } },
                onCancel: { Task { await closeRedemptionSheet() } }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedFreeFitbitesReward) { _, reward in
            if reward == nil {
                pollingTask?.cancel()
                pollingTask = nil
                redemptionSession = nil
                rewardErrorMessage = nil
            }
        }
    }

    private var achievementsMiniatureWidget: some View {
        VStack(spacing: 0) {
            Image("RewardsHero")
                .resizable()
                .scaledToFill()
                .frame(height: 176)
                .clipped()

            achievementsCard
        }
        .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.58)))
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
    }

    private var rewardsHero: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    RewardsLedgerLine(label: "Name", value: dashboard.name)
                    RewardsLedgerLine(label: "Member since", value: dashboard.memberSince)
                    RewardsLedgerLine(label: "Tier", value: dashboard.tierName)
                }

                Spacer(minLength: 8)

                VStack(spacing: 3) {
                    Text("Level")
                        .font(.custom("AvenirNext-Regular", size: 9))
                        .tracking(1.25)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.52))
                    Text("\(rewards.level)")
                        .font(.custom("AvenirNext-DemiBold", size: 34))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FBColors.tielYellow, FBColors.cookieOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: FBColors.cookieOrange.opacity(0.72), radius: 14)
                }
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.055), in: Circle())
                .overlay(Circle().stroke(FBColors.cookieOrange.opacity(0.32)))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(rewards.xp.formatted()) XP")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .tracking(1.1)
                    Spacer()
                    Text("\(rewards.xpToNext) XP to next")
                        .font(.custom("AvenirNext-Regular", size: 10))
                        .tracking(0.95)
                        .foregroundStyle(.white.opacity(0.54))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [FBColors.tielYellow, FBColors.cookieOrange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, proxy.size.width * animatedXPProgress))
                            .shadow(color: FBColors.cookieOrange.opacity(0.65), radius: 8)
                    }
                }
                .frame(height: 6)
            }

            HStack {
                RewardsLedgerLine(label: "Rewards unlocked", value: "\(rewards.rewardsReady)")
                Spacer()
                Text("Ledger")
                    .font(.custom("AvenirNext-Regular", size: 9))
                    .tracking(1.45)
                    .textCase(.uppercase)
                    .foregroundStyle(FBColors.cookieOrange.opacity(0.82))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.052, blue: 0.048).opacity(0.98),
                    Color(red: 0.125, green: 0.115, blue: 0.102).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: FBCorner.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FBCorner.card)
                .stroke(FBColors.cookieOrange.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
    }

    private struct RewardsLedgerLine: View {
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.custom("AvenirNext-Regular", size: 8.5))
                    .tracking(1.35)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.44))
                Text(value)
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .tracking(0.82)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
    }

    private var loyaltyCard: some View {
        VStack(alignment: .leading, spacing: FBSpacing.md) {
            HStack {
                Text("Loyalty stamp card")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .tracking(1.55)
                    .textCase(.uppercase)
                    .foregroundStyle(FBColors.charcoal)
                Spacer()
                Button {} label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FBColors.muted)
                .accessibilityLabel("How loyalty stamps work")
            }

            LoyaltyStampGrid(completed: rewards.loyaltyStamps, total: rewards.loyaltyTarget)

            Text("Collect 9 stamps. Get 1 free reward.")
                .font(.custom("AvenirNext-Regular", size: 11))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
    }

    private var freeFitbitesRewardCard: some View {
        Button {
            guard rewards.rewardsReady > 0, let reward = rewards.freeFitbitesRewards.first else { return }
            selectedFreeFitbitesReward = reward
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Free Reward")
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                            .tracking(1.55)
                            .textCase(.uppercase)
                            .foregroundStyle(FBColors.charcoal)
                        Text(rewards.rewardsReady > 0 ? "Free reward ready" : "\(max(0, rewards.loyaltyTarget - rewards.loyaltyStamps)) stamps to go")
                            .font(.custom("AvenirNext-Regular", size: 13))
                            .foregroundStyle(FBColors.muted)
                    }

                    Spacer()

                    Text("\(rewards.rewardsReady)")
                        .font(.custom("AvenirNext-DemiBold", size: 34))
                        .foregroundStyle(FBColors.cookieOrange)
                        .frame(width: 54, height: 54)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(FBColors.cookieOrange.opacity(0.24)))
                }

                if let reward = rewards.freeFitbitesRewards.first {
                    Text(reward.benefitDescription)
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .foregroundStyle(FBColors.charcoal.opacity(0.72))
                        .multilineTextAlignment(.leading)
                }

                if rewards.rewardsReady > 0 && !rewards.freeFitbitesRedemptionEnabled {
                    Text("Redemption is not available yet.")
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .foregroundStyle(FBColors.charcoal)
                }
            }
            .padding(FBSpacing.md)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
        }
        .buttonStyle(.plain)
        .disabled(rewards.rewardsReady < 1 || rewards.freeFitbitesRewards.isEmpty || !rewards.freeFitbitesRedemptionEnabled)
    }

    private func createRedemptionSession(for reward: FreeFitbitesReward) async {
        guard let client = appState.customerAPIClient else { return }
        isCreatingRedemptionSession = true
        rewardErrorMessage = nil
        defer { isCreatingRedemptionSession = false }

        do {
            let envelope = try await client.createFreeFitbitesRedemptionSession(
                rewardID: reward.id,
                idempotencyKey: "ios-reward-\(reward.id)-\(UUID().uuidString)"
            )
            guard let session = CustomerV2Mapper.redemptionSession(from: envelope) else {
                rewardErrorMessage = "Could not create this reward QR."
                return
            }
            redemptionSession = session
            startPolling(sessionID: session.id)
        } catch {
            rewardErrorMessage = error.localizedDescription
        }
    }

    private func startPolling(sessionID: String) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let client = appState.customerAPIClient else { return }
                do {
                    let envelope = try await client.freeFitbitesRedemptionSession(id: sessionID)
                    guard let session = CustomerV2Mapper.redemptionSession(from: envelope) else { continue }
                    await MainActor.run {
                        redemptionSession = session
                    }
                    if ["completed", "expired", "cancelled"].contains(session.status) {
                        await appState.refreshDashboardAndRewards()
                        return
                    }
                } catch {
                    await MainActor.run {
                        rewardErrorMessage = error.localizedDescription
                    }
                    return
                }
            }
        }
    }

    private func closeRedemptionSheet() async {
        pollingTask?.cancel()
        pollingTask = nil

        if let sessionID = redemptionSession?.id, let client = appState.customerAPIClient {
            try? await client.cancelFreeFitbitesRedemptionSession(id: sessionID)
            await appState.refreshDashboardAndRewards()
        }

        selectedFreeFitbitesReward = nil
    }

    private var ricoStoreCard: some View {
        VStack(alignment: .leading, spacing: FBSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rico's Store")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .tracking(1.55)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.charcoal)
                    Text("\(rewards.ricoWallet.balance) Rico Coins")
                        .font(.custom("AvenirNext-DemiBold", size: 24))
                        .foregroundStyle(FBColors.charcoal)
                }

                Spacer()

                Text("\(rewards.ricoWallet.todayEarned)/\(rewards.ricoWallet.dailyMax) today")
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .tracking(0.8)
                    .foregroundStyle(FBColors.muted)
            }

            if let message = appState.ricoStoreErrorMessage {
                Text(message)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .foregroundStyle(FBColors.charcoal)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.compact))
                    .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.58)))
            }

            if rewards.ricoStoreItems.isEmpty {
                Text("Rico is loading the vault.")
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(FBColors.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(rewards.ricoStoreItems) { item in
                        RicoStoreItemRow(
                            item: item,
                            isPurchasing: appState.ricoPurchaseIDsInFlight.contains(item.id),
                            canAttemptPurchase: appState.canAttemptRicoStorePurchase
                        ) {
                            Task { await appState.purchaseRicoStoreItem(item) }
                        }
                    }
                }
            }
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
    }

    private var achievementsCard: some View {
        NavigationLink {
            AccountAchievementsView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Achievements")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .tracking(1.55)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.charcoal)
                    Text("View badges and milestones")
                        .font(.custom("AvenirNext-Regular", size: 11))
                        .tracking(0.65)
                        .foregroundStyle(FBColors.muted)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FBColors.cookieOrange)
                    .frame(width: 30, height: 30)
                    .background(FBColors.cookieOrange.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(FBColors.cookieOrange.opacity(0.24)))
            }
            .padding(FBSpacing.md)
            .background(Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Achievements")
    }

    private var oldRewardsBody: some View {
        VStack(alignment: .leading, spacing: FBSpacing.lg) {
            FBXPProgress(level: rewards.level, xp: rewards.xp, xpToNext: rewards.xpToNext, targetXP: rewards.levelTarget)

            VStack(alignment: .leading, spacing: FBSpacing.md) {
                    HStack {
                        Text("Loyalty stamps")
                            .font(.fbHeadline(.bold))
                        Spacer()
                        Button {} label: {
                            Label("How it works", systemImage: "info.circle")
                                .font(.fbCaption())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(FBColors.muted)
                        .accessibilityLabel("How loyalty stamps work")
                    }
                    LoyaltyStampGrid(completed: rewards.loyaltyStamps, total: rewards.loyaltyTarget)
                }
                .padding(FBSpacing.md)
                .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))

                VStack(alignment: .leading, spacing: FBSpacing.md) {
                    HStack {
                        Text("Achievements")
                            .font(.fbHeadline(.bold))
                        Spacer()
                        Text("View all")
                            .font(.fbCaption())
                            .foregroundStyle(FBColors.muted)
                    }

                    HStack(spacing: 13) {
                        ForEach(rewards.achievements) { achievement in
                            AchievementMedallion(achievement: achievement)
                        }
                    }
                }

                rewardMoment
        }
    }

    private var rewardMoment: some View {
        HStack(alignment: .bottom, spacing: FBSpacing.md) {
            CharacterBubble(name: "Too", symbol: "flame.fill", tint: FBColors.cookieOrange, size: 82)
            CharacterBubble(name: "Tiel", symbol: "checkmark.seal.fill", tint: FBColors.tielYellow, size: 82)
            Spacer()
            VStack(spacing: 6) {
                Text("\(rewards.rewardsReady)")
                    .font(.custom("AvenirNext-DemiBold", size: 28))
                Text("rewards\nready")
                    .font(.fbCaption(.semibold))
                    .multilineTextAlignment(.center)
                Image(systemName: "gift.fill")
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(FBColors.cookieOrange, in: Circle())
            }
            .foregroundStyle(FBColors.charcoal)
            .padding(FBSpacing.md)
            .background(FBColors.card, in: RoundedRectangle(cornerRadius: FBCorner.card))
        }
        .padding(.top, 6)
    }
}

private struct FreeFitbitesRedemptionSheet: View {
    let reward: FreeFitbitesReward
    let session: FreeFitbitesRedemptionSession?
    let errorMessage: String?
    let isCreatingSession: Bool
    let onShowQR: () -> Void
    let onCancel: () -> Void

    private var statusText: String {
        switch session?.status {
        case "pending":
            return "Waiting for staff"
        case "scanned":
            return "Reward reserved"
        case "completed":
            return "Reward redeemed"
        case "expired":
            return "This QR expired"
        case "cancelled":
            return "Reward returned"
        default:
            return "Ready to redeem your reward?"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(FBColors.line)
                .frame(width: 42, height: 4)
                .padding(.top, 10)

            VStack(spacing: 8) {
                Text(reward.name)
                    .font(.custom("AvenirNext-DemiBold", size: 28))
                    .foregroundStyle(FBColors.charcoal)
                Text(statusText)
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(FBColors.charcoal.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            if let session, let qrToken = session.qrToken, ["pending", "scanned"].contains(session.status) {
                QRCodeImage(payload: qrToken)
                    .frame(width: 240, height: 240)
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(FBColors.line.opacity(0.7)))

                Text(session.fallbackCode.map { "Code \($0)" } ?? "Show this to Fitbites staff")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .tracking(1.0)
                    .foregroundStyle(FBColors.charcoal)

                Text("Show this to Fitbites staff")
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(FBColors.muted)
            } else {
                Text(reward.benefitDescription)
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(FBColors.charcoal.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(FBColors.charcoal)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.compact))
            }

            Spacer()

            if session == nil || session?.status == "expired" || session?.status == "cancelled" {
                Button(action: onShowQR) {
                    Text(isCreatingSession ? "CREATING QR" : "SHOW QR CODE")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(FBColors.cookieOrange, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isCreatingSession)
            }

            Button(action: onCancel) {
                Text("NOT NOW")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .tracking(1.1)
                    .foregroundStyle(FBColors.charcoal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(FBColors.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(FBSpacing.md)
        .background(Color.white)
    }
}

private struct QRCodeImage: View {
    let payload: String
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = qrImage {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            ProgressView()
        }
    }

    private var qrImage: UIImage? {
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

private struct RicoStoreItemRow: View {
    let item: RicoStoreItem
    let isPurchasing: Bool
    let canAttemptPurchase: Bool
    let purchase: () -> Void

    private var stateText: String {
        if isPurchasing { return "Buying" }
        if !canAttemptPurchase { return "Offline" }
        if item.isOwned { return "Owned" }
        if let remaining = item.remainingStock, remaining <= 0 { return "Sold out" }
        if let lockReason = item.lockReason { return lockReason }
        if item.isLimited { return "Limited" }
        return "\(item.coinPrice) coins"
    }

    private var canPurchase: Bool {
        canAttemptPurchase && item.isAvailable && !item.isOwned && !isPurchasing
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: FBCorner.compact)
                    .fill(Color.white)
                Image(systemName: item.isLimited ? "shippingbox.fill" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FBColors.cookieOrange)
            }
            .frame(width: 46, height: 46)
            .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.58)))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.custom("AvenirNext-DemiBold", size: 14))
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)
                Text(item.shortDescription)
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(FBColors.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: purchase) {
                Text(stateText)
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .tracking(0.6)
                    .foregroundStyle(canPurchase ? .white : FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 82, height: 36)
                    .background(canPurchase ? FBColors.cookieOrange : Color.white, in: RoundedRectangle(cornerRadius: FBCorner.compact))
                    .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(canPurchase ? 0 : 0.7)))
            }
            .buttonStyle(.plain)
            .disabled(!canPurchase)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.58)))
        .accessibilityLabel("\(item.name), \(stateText)")
    }
}

private struct AchievementMedallion: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.24, blue: 0.13), Color(red: 0.86, green: 0.62, blue: 0.30)], startPoint: .bottom, endPoint: .top))
                Image(systemName: achievement.systemImage)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(FBColors.card)
            }
            .frame(width: 78, height: 78)
            .overlay(Circle().stroke(FBColors.tielYellow.opacity(0.65), lineWidth: 2))

            Text(achievement.title)
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(FBColors.charcoal)
                .lineLimit(2)
                .frame(height: 28)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(achievement.title)
    }
}
