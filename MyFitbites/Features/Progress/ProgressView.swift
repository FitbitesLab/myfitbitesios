import AudioToolbox
import SwiftUI

struct ProgressTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isArtworkVisible = false
    @State private var isPanelVisible = false
    @State private var areProductsVisible = false
    @State private var isIntroPresented = false
    @State private var isClearanceCardPresented = false

    private var dashboard: CustomerDashboard {
        appState.dashboardRepository.dashboard()
    }

    private var labAccess: TooLabAccessState {
        TooLabAccessState(dashboard: dashboard, labXP: appState.tooLabProgress.totalLXP)
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        labHero(width: proxy.size.width, height: proxy.size.height * 0.30 + proxy.safeAreaInsets.top + 28)
                            .offset(y: -proxy.safeAreaInsets.top)
                            .opacity(isArtworkVisible ? 1 : 0)
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(FBColors.line)
                            .frame(width: 34, height: 4)
                            .padding(.top, 12)
                            .padding(.bottom, 14)
                            .accessibilityHidden(true)

                        Button {
                            isClearanceCardPresented = true
                        } label: {
                            LabClearanceCard(access: labAccess)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, FBSpacing.md)
                        .zIndex(1)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                labProducts

                                Button(action: presentIntro) {
                                    Label("What is Too's Lab?", systemImage: "info.circle")
                                        .font(.custom("AvenirNext-DemiBold", size: 12))
                                        .foregroundStyle(Color.purple)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, FBSpacing.md)
                            .padding(.top, 44)
                            .padding(.bottom, proxy.safeAreaInsets.bottom + 28)
                        }
                        .modifier(LabProductScrollEdgeModifier())
                        .mask {
                            VStack(spacing: 0) {
                                LinearGradient(
                                    colors: [.clear, .black],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 28)
                                Rectangle().fill(.black)
                            }
                        }
                        // The fade sits underneath the XP card, not in a strip below it.
                        .padding(.top, -28)
                        .opacity(areProductsVisible ? 1 : 0)
                        .offset(y: areProductsVisible ? 0 : 18)
                        .allowsHitTesting(areProductsVisible)
                        .accessibilityHidden(!areProductsVisible)
                    }
                    .frame(height: proxy.size.height * 0.70 + proxy.safeAreaInsets.bottom)
                    .frame(maxWidth: .infinity)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.12), radius: 20, y: -6)
                    }
                    .offset(y: isPanelVisible ? 0 : proxy.size.height)
                    .allowsHitTesting(isPanelVisible)
                    .accessibilityHidden(!isPanelVisible)
                    // Clip the entrance at the screen edge, allowing products behind the bar.
                    .frame(height: proxy.size.height + proxy.safeAreaInsets.bottom, alignment: .bottom)
                    .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.bottom, alignment: .bottom)
                .background(Color.white.ignoresSafeArea())
                .navigationTitle("Too's Lab")
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .tabBar)
                .onAppear {
                    presentIntroIfNeeded()
                    Task { await appState.refreshTooLabProgress() }
                }
                .onChange(of: appState.selectedTab) { _, _ in
                    presentIntroIfNeeded()
                }
                .onChange(of: appState.currentCustomerID) { _, _ in
                    isIntroPresented = false
                    presentIntroIfNeeded()
                }
                .task(id: shouldAnimateEntrance) {
                    await animateEntrance()
                }
                .sheet(isPresented: $isClearanceCardPresented) {
                    LabClearanceLevelsCard(access: labAccess)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.hidden)
                }
            }

            if isIntroPresented {
                TooLabIntroView {
                    dismissIntro()
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.62, dampingFraction: 0.9), value: isIntroPresented)
    }

    private var shouldAnimateEntrance: Bool {
        appState.selectedTab == .progress && !isIntroPresented
    }

    @MainActor
    private func animateEntrance() async {
        // Keep the current composition intact while another tab replaces the Lab.
        guard shouldAnimateEntrance else { return }
        isArtworkVisible = false
        isPanelVisible = false
        areProductsVisible = false
        if reduceMotion {
            isArtworkVisible = true
            isPanelVisible = true
            areProductsVisible = true
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(500))
            withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                isPanelVisible = true
            }
            try await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.45)) {
                isArtworkVisible = true
                areProductsVisible = true
            }
        } catch {
            // Leaving the Lab cancels the entrance sequence.
        }
    }

    @ViewBuilder
    private var labProducts: some View {
                            if !labAccess.isLabUnlocked {
                                LabPrototypePreviewSection(access: labAccess)

                            } else {
                                if labAccess.canAccessPrototypeDrops {
                                    HStack {
                                        Text("ACTIVE EXPERIMENT")
                                            .font(.custom("AvenirNext-DemiBold", size: 16))
                                            .tracking(0.8)
                                            .foregroundStyle(FBColors.charcoal)

                                        Spacer()

                                        HStack(spacing: 5) {
                                            Text("See all experiments")
                                            Image(systemName: "arrow.right")
                                        }
                                        .font(.custom("AvenirNext-DemiBold", size: 12))
                                        .foregroundStyle(FBColors.caramel)
                                    }

                                    ActiveFoodExperimentCard(access: labAccess, prototype: labAccess.featuredPrototype)
                                } else {
                                    LabPrototypePreviewSection(access: labAccess)
                                }


                                LabTodayChecklistCard(access: labAccess)
                                LabResearchArchiveCard()
                            }
    }

    private func presentIntroIfNeeded() {
        guard appState.selectedTab == .progress, !hasSeenIntroForCurrentCustomer, !isIntroPresented else { return }
        DispatchQueue.main.async {
            presentIntro()
        }
    }

    private func presentIntro() {
        withAnimation(.spring(response: 0.62, dampingFraction: 0.9)) {
            isIntroPresented = true
        }
    }

    private func dismissIntro() {
        markIntroSeenForCurrentCustomer()
        withAnimation(.easeInOut(duration: 0.32)) {
            isIntroPresented = false
        }
    }

    private var hasSeenIntroForCurrentCustomer: Bool {
        guard let introSeenKey else { return true }
        return UserDefaults.standard.bool(forKey: introSeenKey)
    }

    private func markIntroSeenForCurrentCustomer() {
        guard let introSeenKey else { return }
        UserDefaults.standard.set(true, forKey: introSeenKey)
    }

    private var introSeenKey: String? {
        guard let customerID = appState.currentCustomerID else { return nil }
        return "TooLabHasSeenIntro.user.\(customerID)"
    }

    private func labHero(width: CGFloat, height: CGFloat) -> some View {
        Image("TooLabHero")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .accessibilityHidden(true)
    }

}

// Keep the product list visible behind the native bar without a system edge scrim.
private struct LabProductScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            content
        }
    }
}

private struct TooLabIntroView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(FBColors.charcoal)
                            .frame(width: 38, height: 38)
                            .background(FBColors.surface, in: Circle())
                            .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Too's Lab intro")
                }
                .padding(.horizontal, FBSpacing.md)
                .padding(.top, 18)

                Spacer(minLength: 8)

                Image("TooLabScientistIntro")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 380, maxHeight: 360)
                    .offset(x: -14)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)

                Text("Experimental")
                    .font(.custom("AvenirNext-DemiBold", size: 38))
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)

                Text(.init("Too's experiments need brave volunteers.\nPlay experiments to earn **Lab XP**, raise your clearance, gain access to higher clearance, and unlock secret Fitbites prototypes you can actually order.\n*Tiel accepts no responsibility for what happens next.*"))
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(FBColors.charcoal.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.top, 12)
                    .padding(.horizontal, FBSpacing.md)

                Spacer(minLength: 22)

                Button(action: onDismiss) {
                    Text("ENTER TOO'S LAB")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, FBSpacing.md)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct TooLabIntroRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.purple)
                .frame(width: 38, height: 38)
                .background(Color.purple.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(FBColors.charcoal)

                Text(subtitle)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .foregroundStyle(FBColors.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}

struct TooLabAccessState {
    let level: Int
    let labXP: Int
    let currentXP: Int
    let targetXP: Int
    let milestones: [TooLabAccessMilestone]
    let prototypePreviews: [TooLabPrototypeDrop]
    let featuredPrototype: TooLabPrototypeDrop

    init(dashboard: CustomerDashboard, labXP: Int) {
        self.level = dashboard.level
        self.labXP = max(0, labXP)
        self.currentXP = max(0, labXP)
        self.targetXP = TooLabClearance.next(afterLabXP: max(0, labXP))?.requiredLabXP ?? max(1, labXP)
        self.milestones = TooLabClearance.allCases.map(TooLabAccessMilestone.init(clearance:))
        self.prototypePreviews = [
            TooLabPrototypeDrop(
                id: "choco-mulberry-crunch",
                experimentCode: "EXPERIMENT #017",
                name: "CHOCO MULBERRY CRUNCH",
                subtitle: "Chocolate. Mulberry. Crunch.",
                priceText: "79K",
                imageName: "ProductGreekYogurtBlueberry",
                requiredClearance: .restrictedAccess
            ),
            TooLabPrototypeDrop(
                id: "crepe-reactor-berry",
                experimentCode: "EXPERIMENT #021",
                name: "CREPE REACTOR BERRY",
                subtitle: "Protein crepe under review.",
                priceText: "69K",
                imageName: "ProductProteinCrepe",
                requiredClearance: .highSecurity
            ),
            TooLabPrototypeDrop(
                id: "omega-cacao-oats",
                experimentCode: "EXPERIMENT #024",
                name: "OMEGA CACAO OATS",
                subtitle: "Dark cacao test batch.",
                priceText: "89K",
                imageName: "ProductTiramiOats",
                requiredClearance: .classified
            )
        ]
        self.featuredPrototype = prototypePreviews[0]
    }

    var clearance: TooLabClearance {
        TooLabClearance.current(forLabXP: labXP)
    }

    var nextClearance: TooLabClearance? {
        TooLabClearance.next(afterLabXP: labXP)
    }

    var labUnlockLevel: Int { 5 }
    var isLabUnlocked: Bool { level >= labUnlockLevel }
    var isOrientation: Bool { !isLabUnlocked }
    var canAccessArcade: Bool { level >= 1 }
    var canAccessPrototypeDrops: Bool { isLabUnlocked && canBuy(featuredPrototype) }

    var clearanceProgress: Double {
        guard isLabUnlocked else { return 0 }

        let previousXP = TooLabClearance.allCases
            .filter { $0.requiredLabXP < targetXP }
            .last?
            .requiredLabXP ?? 0
        let span = max(1, targetXP - previousXP)
        let earned = max(0, min(labXP, targetXP) - previousXP)

        return min(1, max(0, Double(earned) / Double(span)))
    }

    var nextMilestone: TooLabAccessMilestone? {
        nextClearance.map(TooLabAccessMilestone.init(clearance:))
    }

    var clearanceTitle: String {
        isLabUnlocked ? clearance.title : "ACCESS DENIED"
    }

    var visibleClearanceCode: String {
        isLabUnlocked ? clearance.code : ""
    }

    var clearanceMessage: String {
        if !isLabUnlocked {
            return ""
        }

        if let nextClearance {
            let remaining = max(0, nextClearance.requiredLabXP - labXP)
            return "\(remaining) LXP until \(nextClearance.code) \(nextClearance.title)."
        }

        return "All current lab clearances unlocked."
    }

    func hasClearance(_ requiredClearance: TooLabClearance) -> Bool {
        isLabUnlocked && clearance.rawValue >= requiredClearance.rawValue
    }

    func isCurrent(_ candidate: TooLabClearance) -> Bool {
        isLabUnlocked && clearance == candidate
    }

    func canBuy(_ prototype: TooLabPrototypeDrop) -> Bool {
        hasClearance(prototype.requiredClearance)
    }
}

struct TooLabAccessMilestone: Identifiable {
    let clearance: TooLabClearance
    let title: String
    let subtitle: String

    init(clearance: TooLabClearance) {
        self.clearance = clearance
        self.title = clearance.title
        self.subtitle = clearance.subtitle
    }

    var id: Int { clearance.id }
}

struct TooLabPrototypeDrop: Identifiable {
    let id: String
    let experimentCode: String
    let name: String
    let subtitle: String
    let priceText: String
    let imageName: String
    let requiredClearance: TooLabClearance
}

private struct LabClearanceCard: View {
    let access: TooLabAccessState

    private var isLocked: Bool {
        !access.isLabUnlocked
    }

    private var tint: Color {
        isLocked ? Color.purple : access.clearance.color
    }

    private var progress: Double {
        access.clearanceProgress
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(access.clearanceTitle)
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .tracking(0.8)
                        .foregroundStyle(isLocked ? Color.purple : FBColors.charcoal)

                    if !access.visibleClearanceCode.isEmpty {
                        Text(access.visibleClearanceCode)
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                            .foregroundStyle(tint)
                    }

                    Spacer()

                    if !isLocked {
                        Text("\(access.labXP) LXP")
                            .font(.custom("AvenirNext-DemiBold", size: 11))
                            .foregroundStyle(tint)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isLocked ? FBColors.line.opacity(0.62) : tint.opacity(0.16))

                        if !isLocked {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [tint, tint.opacity(0.70)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(12, proxy.size.width * progress))
                        }
                    }
                }
                .frame(height: 7)
                .overlay(Capsule().stroke(isLocked ? FBColors.line.opacity(0.72) : .white.opacity(0.62), lineWidth: 0.7))

                if !access.clearanceMessage.isEmpty {
                    HStack(spacing: 6) {
                        Text(access.clearanceMessage)
                            .font(.custom("AvenirNext-Regular", size: 11))
                            .foregroundStyle(FBColors.charcoal.opacity(0.72))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tint.opacity(0.78))
                    }
                }
            }
        }
        .padding(10)
        .frame(height: 76)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(.white.opacity(0.7)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}

private struct LabOrientationCard: View {
    let access: TooLabAccessState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabSectionHeader(symbol: "sparkles", title: "LEVEL 1 ORIENTATION")

            Text("Too is setting up your bench.")
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(FBColors.charcoal)

            Text("Play the main app, earn XP, and come back as new lab clearance opens. For now, this room is a preview of what you are building toward.")
                .font(.custom("AvenirNext-Regular", size: 13))
                .foregroundStyle(FBColors.muted)
                .lineSpacing(3)

            HStack(spacing: 8) {
                LabOrientationPill(symbol: "lock.open", title: "Joined", tint: access.clearance.color)
                LabOrientationPill(symbol: "flask", title: access.nextClearance.map { "Next: \($0.code)" } ?? "Ready", tint: access.nextClearance?.color ?? access.clearance.color)
            }
        }
        .padding(12)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }
}

private struct LabOrientationPill: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.custom("AvenirNext-DemiBold", size: 11))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tint.opacity(0.10), in: Capsule())
    }
}

private struct LabClearanceLevelsCard: View {
    let access: TooLabAccessState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Capsule()
                    .fill(FBColors.muted.opacity(0.34))
                    .frame(width: 56, height: 5)
                Spacer()
            }
            .padding(.top, 4)
            .padding(.bottom, 10)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAB CLEARANCE")
                        .font(.custom("AvenirNext-DemiBold", size: 18))
                        .tracking(0.9)
                        .foregroundStyle(FBColors.charcoal)

                    Text("\(access.labXP) LXP")
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(FBColors.muted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close clearance levels")
            }

            VStack(spacing: 0) {
                ForEach(access.milestones) { milestone in
                    LabClearanceLevelRow(
                        milestone: milestone,
                        isCurrent: access.isCurrent(milestone.clearance),
                        isUnlocked: access.hasClearance(milestone.clearance)
                    )

                    if milestone.id != access.milestones.last?.id {
                        Divider()
                            .padding(.leading, 64)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, FBSpacing.md)
        .background(Color.white.ignoresSafeArea())
    }
}

private struct LabClearanceLevelRow: View {
    let milestone: TooLabAccessMilestone
    let isCurrent: Bool
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(milestone.clearance.color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                .shadow(color: milestone.clearance.color.opacity(0.28), radius: 6, y: 3)

            Text(milestone.clearance.code)
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(.white)
                .frame(width: 36, height: 24)
                .background(milestone.clearance.color, in: Capsule())

            Text(milestone.title)
                .font(.custom("AvenirNext-DemiBold", size: 14))
                .tracking(0.5)
                .foregroundStyle(isUnlocked ? FBColors.charcoal : FBColors.muted)

            Spacer()

            if isCurrent {
                Text("CURRENT")
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .tracking(0.7)
                    .foregroundStyle(milestone.clearance.color)
            } else if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FBColors.muted.opacity(0.55))
            }
        }
        .frame(height: 50)
        .padding(.horizontal, 12)
    }
}

private struct LabSectionHeader: View {
    let symbol: String
    let title: String
    var actionTitle: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.purple)

            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .tracking(0.8)
                .foregroundStyle(FBColors.charcoal)

            Spacer()

            if let actionTitle {
                HStack(spacing: 5) {
                    Text(actionTitle)
                    Image(systemName: "arrow.right")
                }
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(FBColors.caramel)
            }
        }
    }
}

private struct LabPrototypePreviewSection: View {
    let access: TooLabAccessState

    var body: some View {
        VStack(spacing: 10) {
            ForEach(access.prototypePreviews) { prototype in
                PrototypePreviewTile(access: access, prototype: prototype)
            }
        }
    }
}

private struct PrototypePreviewTile: View {
    let access: TooLabAccessState
    let prototype: TooLabPrototypeDrop

    private var tint: Color {
        prototype.requiredClearance.color
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(prototype.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 126, height: 118)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text(prototype.requiredClearance.code)
                        .font(.custom("AvenirNext-DemiBold", size: 10))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(tint, in: Capsule())
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(prototype.experimentCode)
                    .font(.custom("AvenirNext-DemiBold", size: 9))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Text(prototype.name)
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(prototype.priceText)
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(FBColors.charcoal)

                Text("\(prototype.requiredClearance.title) REQUIRED")
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .tracking(0.7)
                    .foregroundStyle(FBColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(access.canBuy(prototype) ? "ACCESS GRANTED" : "ACCESS DENIED")
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .tracking(0.9)
                    .foregroundStyle(access.canBuy(prototype) ? tint : Color.purple)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke((access.canBuy(prototype) ? tint : Color.purple).opacity(0.48)))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }
}

struct ActiveFoodExperimentCard: View {
    @EnvironmentObject private var appState: AppState
    let access: TooLabAccessState
    let prototype: TooLabPrototypeDrop
    @State private var purchaseMessage: String?
    @State private var isPurchasing = false

    private var tint: Color {
        prototype.requiredClearance.color
    }

    private var canBuy: Bool {
        access.canBuy(prototype)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Image(prototype.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 150)
                    .clipped()

                Text("NEW\nTESTING")
                    .font(.custom("AvenirNext-DemiBold", size: 9))
                    .foregroundStyle(FBColors.charcoal)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .rotationEffect(.degrees(-8))
                    .padding(9)
            }
            .frame(width: 132, height: 150)

            VStack(alignment: .leading, spacing: 7) {
                Text(prototype.experimentCode)
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .tracking(0.7)
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Text(prototype.name)
                    .font(.custom("AvenirNext-DemiBold", size: 17))
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(prototype.subtitle)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .foregroundStyle(FBColors.muted)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    Label(prototype.priceText, systemImage: "tag")
                    Label("\(prototype.requiredClearance.code) REQUIRED", systemImage: "lock")
                }
                .font(.custom("AvenirNext-DemiBold", size: 13))
                .foregroundStyle(FBColors.muted)

                if let purchaseMessage {
                    Text(purchaseMessage)
                        .font(.custom("AvenirNext-DemiBold", size: 11))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(2)
                }

                Button {
                    Task { await purchasePrototype() }
                } label: {
                    HStack {
                        Text(isPurchasing ? "RESERVING" : canBuy ? "TASTE THE EXPERIMENT" : "ACCESS DENIED")
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                            .tracking(0.9)
                        Spacer()
                        Image(systemName: isPurchasing ? "hourglass" : canBuy ? "arrow.right" : "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(canBuy ? tint : FBColors.charcoal.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canBuy || isPurchasing)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .padding(.leading, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.trailing, 10)
        }
        .frame(height: 162)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }

    private func purchasePrototype() async {
        guard canBuy, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        let awarded = await appState.purchaseTooLabPrototype(identifier: prototype.id)
        purchaseMessage = awarded > 0 ? "Prototype order sent. +\(awarded) LXP." : "Prototype order already sent."
    }
}

private struct LabFieldReportCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("TooLabHomeCard")
                .resizable()
                .scaledToFill()
                .frame(width: 108, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "clipboard.fill")
                    Text("FIELD REPORT")
                }
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .foregroundStyle(Color.purple)

                Text("TOO NEEDS YOUR FINDINGS")
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(2)

                Text("Experiment #017 is awaiting review.")
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(FBColors.muted)

                HStack {
                    Text("FILE REPORT")
                    Spacer()
                    Image(systemName: "arrow.right")
                    Text("+100 LAB XP")
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .foregroundStyle(Color.purple)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.45)))
            }
        }
        .padding(10)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(alignment: .topTrailing) {
            Text("1")
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.red, in: Circle())
                .padding(10)
        }
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }
}

private struct LabArcadeEntryCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.purple.opacity(0.12))

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.purple.opacity(0.84))
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("The Arcade Experiment")
                        .font(.custom("AvenirNext-DemiBold", size: 18))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("Puzzle, memory, scratch rewards.")
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(FBColors.muted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FBColors.charcoal)
                    .frame(width: 34, height: 34)
                    .background(FBColors.card, in: Circle())
                    .overlay(Circle().stroke(FBColors.line.opacity(0.58)))
            }
            .padding(14)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open The Arcade Experiment")
    }
}

private struct LabArcadeTeaserCard: View {
    @EnvironmentObject private var appState: AppState
    let action: () -> Void
    @AppStorage("LabPuzzleBestMoves") private var bestMoves = 0

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: LabArcadeGame.puzzle.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabSectionHeader(
                symbol: "gamecontroller.fill",
                title: "THE ARCADE EXPERIMENT",
                actionTitle: "Daily tests"
            )

            HStack(spacing: 0) {
                ForEach(LabArcadeGame.allCases) { game in
                    HStack(spacing: 7) {
                        Image(systemName: game.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        Text(game.title)
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                    }
                    .foregroundStyle(game == .puzzle ? .white : FBColors.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(game == .puzzle ? Color.purple : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(3)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(FBColors.line.opacity(0.6)))

            HStack(spacing: 10) {
                PuzzlePreview()
                    .frame(width: 112, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "puzzlepiece.fill")
                        Text("TODAY'S LAB GAME")
                    }
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .foregroundStyle(Color.purple)

                    Text("Secret Lab Puzzle")
                        .font(.custom("AvenirNext-DemiBold", size: 16))
                        .foregroundStyle(FBColors.charcoal)

                    Text("Slide one tile at a time.")
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .foregroundStyle(FBColors.muted)

                    HStack(spacing: 16) {
                        LabMiniStat(title: "BEST", value: bestMoves > 0 ? "\(bestMoves)" : "--")
                        LabMiniStat(title: "TODAY'S REWARD", value: hasClaimedDailyReward ? "CLAIMED" : "+\(appState.tooLabProgress.dailyGameXP) LXP")
                    }
                }

                Spacer(minLength: 0)

                Button(action: action) {
                    Text("PLAY")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 46)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
        }
    }
}

private struct PuzzlePreview: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width / 3

            ZStack(alignment: .topLeading) {
                ForEach(0..<9, id: \.self) { index in
                    let row = index / 3
                    let column = index % 3

                    if index == 4 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(FBColors.surface)
                            .frame(width: size, height: size)
                            .offset(x: CGFloat(column) * size, y: CGFloat(row) * size)
                    } else {
                        Image("TooLabHomeCard")
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.width)
                            .offset(x: -CGFloat(column) * size, y: -CGFloat(row) * size)
                            .frame(width: size, height: size)
                            .clipped()
                            .offset(x: CGFloat(column) * size, y: CGFloat(row) * size)
                    }
                }
            }
        }
    }
}

private struct LabMiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 9))
                .tracking(0.8)
                .foregroundStyle(FBColors.muted)
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(Color.purple)
                .lineLimit(1)
        }
    }
}

private struct LabTodayChecklistCard: View {
    @EnvironmentObject private var appState: AppState
    let access: TooLabAccessState

    private var earnedXP: Int {
        appState.tooLabProgress.dailyGames.reduce(0) { $0 + $1.xpAwarded }
    }

    private var progress: Double {
        Double(earnedXP) / Double(max(1, appState.tooLabProgress.dailyGameXP * 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabSectionHeader(symbol: "clipboard.fill", title: "TODAY IN THE LAB")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(earnedXP) / 100")
                        .font(.custom("AvenirNext-DemiBold", size: 16))
                        .foregroundStyle(FBColors.charcoal)
                    Text("LXP EARNED TODAY")
                        .font(.custom("AvenirNext-DemiBold", size: 9))
                        .tracking(0.8)
                        .foregroundStyle(FBColors.muted)
                }
            }

            HStack(spacing: 6) {
                LabDailyTaskPill(symbol: "puzzlepiece.fill", title: "Puzzle", isComplete: appState.tooLabProgress.hasClaimed(game: LabArcadeGame.puzzle.rawValue))
                LabDailyTaskPill(symbol: "rectangle.on.rectangle.angled", title: "Memory", isComplete: appState.tooLabProgress.hasClaimed(game: LabArcadeGame.memory.rawValue))
                LabDailyTaskPill(symbol: "sparkles", title: "Scratch", isComplete: appState.tooLabProgress.hasClaimed(game: LabArcadeGame.scratch.rawValue))
            }

            ProgressView(value: progress)
                .tint(Color.purple)
        }
        .padding(10)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }
}

private struct LabDailyTaskPill: View {
    let symbol: String
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.purple)

            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 10))
                .foregroundStyle(FBColors.charcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 2)

            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isComplete ? Color.green : FBColors.line)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(FBColors.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(FBColors.line.opacity(0.58)))
    }
}

private struct LabResearchArchiveCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(FBColors.card)
                Image(systemName: "folder.fill.badge.person.crop")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FBColors.caramel)
            }
            .frame(width: 94, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                Text("RESEARCH ARCHIVE")
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .foregroundStyle(Color.purple)

                Text("12 experiments encountered")
                    .font(.custom("AvenirNext-DemiBold", size: 14))
                    .foregroundStyle(FBColors.charcoal)

                Text("4 escaped the Lab")
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .foregroundStyle(FBColors.muted)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FBColors.caramel)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(FBColors.caramel.opacity(0.5)))
        }
        .padding(10)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }
}

struct LabArcadeExperimentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var phase
    @State private var paidRun: ArcadeRun?
    @Environment(\.dismiss) private var dismiss
    @State private var activeGame: LabArcadeGame?
    @State private var selectedGame: LabArcadeGame?
    @State private var pendingGame: LabArcadeGame?

    var body: some View {
        NavigationStack {
            Group {
                if let activeGame {
                    LabArcadeFullscreenGameView(game: activeGame, run: paidRun) {
                        paidRun = nil
                        Task { await appState.refreshArcadeCredits() }
                        self.activeGame = nil
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            RewardsPageHero(artwork: "MyArcadeArtwork", title: "My Arcade")
                                .overlay(alignment: .topLeading) {
                                    RewardsPageBackButton { dismiss() }
                                        .padding(10)
                                }
                            ArcadeCreditBalanceView()
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    Text("Meet your next favourite")
                                        .font(.custom("AvenirNext-DemiBold", size: 20))
                                    Spacer()
                                    Text("\(LabArcadeGame.allCases.count) GAMES")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(FBColors.muted)
                                }
                                ForEach(LabArcadeGame.allCases) { game in
                                    Button { selectedGame = game } label: {
                                        HStack(spacing: 16) {
                                            ArcadeGameIcon(game: game, size: 96)
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(game.storeTitle)
                                                    .font(.custom("AvenirNext-DemiBold", size: 17))
                                                    .foregroundStyle(FBColors.charcoal)
                                                    .multilineTextAlignment(.leading)
                                                Text(game.genre)
                                                    .font(.custom("AvenirNext-Regular", size: 13))
                                                    .foregroundStyle(FBColors.muted)
                                                Text(game.isDemo ? "DEMO" : "PUZZLE")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(game.accent)
                                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                                    .background(game.accent.opacity(0.09), in: Capsule())
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(FBColors.muted.opacity(0.6))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Show game details")
                                    .accessibilityIdentifier("arcade-details-\(game.rawValue)")
                                    if game != LabArcadeGame.allCases.last {
                                        Divider().padding(.leading, 112)
                                    }
                                }
                            }
                            Text("Pick a game to take a closer look.")
                                .font(.custom("AvenirNext-Regular", size: 13))
                                .foregroundStyle(FBColors.muted)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await appState.refreshArcadeCredits() }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await appState.refreshArcadeCredits() } }
        }
        .sheet(item: $selectedGame, onDismiss: {
            // Finish dismissing the portrait drawer before a demo requests landscape.
            guard let pendingGame else { return }
            self.pendingGame = nil
            activeGame = pendingGame
        }) { game in
            ArcadeGameDrawer(game: game) { run in
                paidRun = run
                pendingGame = game
                selectedGame = nil
            }
            .presentationDetents([.height(480), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
    }
}

private struct ArcadeGameIcon: View {
    let game: LabArcadeGame
    let size: CGFloat

    var body: some View {
        Image(game.artwork)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).stroke(.black.opacity(0.06)))
            .accessibilityHidden(true)
    }
}

private struct ArcadeGameDrawer: View {
    let game: LabArcadeGame
    let onPlay: (ArcadeRun) -> Void
    @EnvironmentObject private var appState: AppState
    @State private var isStarting = false
    @State private var startError: String?
    @State private var ranOutOfCredits = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    ArcadeGameIcon(game: game, size: 80)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(game.storeTitle)
                            .font(.custom("AvenirNext-DemiBold", size: 21))
                            .foregroundStyle(FBColors.charcoal)
                        Text(game.genre)
                            .font(.custom("AvenirNext-Regular", size: 14))
                            .foregroundStyle(FBColors.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FBColors.muted)
                            .frame(width: 30, height: 30)
                            .background(FBColors.surface, in: Circle())
                    }.accessibilityLabel("Close game details")
                }
                Text(game.explanation)
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(FBColors.charcoal.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                Label(game.scope, systemImage: game.isDemo ? "gamecontroller" : "square.grid.3x3")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .foregroundStyle(game.accent)
                Text(game.rewardRule)
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(FBColors.muted)
                if ranOutOfCredits {
                    Text("You ran out of credits!")
                        .font(.custom("AvenirNext-DemiBold", size: 15))
                        .foregroundStyle(FBColors.charcoal)
                } else if let startError {
                    Text(startError)
                        .font(.custom("AvenirNext-DemiBold", size: 15))
                        .foregroundStyle(FBColors.charcoal)
                }
                Button {
                    guard !isStarting else { return }
                    isStarting = true
                    startError = nil
                    ranOutOfCredits = false
                    Task {
                        defer { isStarting = false }
                        do { onPlay(try await appState.startArcadeRun(game: game.rawValue)) }
                        catch {
                            if case CustomerV2APIError.validation(_, let fields) = error,
                               fields["credits"] != nil {
                                ranOutOfCredits = true
                                await appState.refreshArcadeCredits()
                            } else {
                                startError = appState.authenticationStatus == .authenticated
                                    ? "Arcade is unavailable right now. Please try again later."
                                    : "Sign in to play."
                            }
                        }
                    }
                } label: {
                    Label(isStarting ? "Starting…" : (game.isDemo ? "Play · 1 credit required" : "Play · 1 credit"), systemImage: "play.fill")
                        .font(.custom("AvenirNext-DemiBold", size: 17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(game.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityIdentifier("arcade-play-\(game.rawValue)")
            }
            .padding(24)
            .padding(.top, 12)
        }
        .background(Color.white)
    }
}

private enum LabArcadeGame: String, CaseIterable, Identifiable {
    case tooDemo = "too_demo"
    case puzzle
    case memory
    case scratch
    case labRun = "lab_run"
    case flappyTiel = "flappy_tiel"
    case pong

    static var allCases: [LabArcadeGame] {
        [.tooDemo, .puzzle]
    }

    var rewardRule: String {
        switch self {
        case .tooDemo: "Too’s Rico reward challenge is coming later."
        default: "Solve the puzzle within 60 seconds to earn 1 Rico coin."
        }
    }

    var isDemo: Bool { self == .tooDemo }

    var storeTitle: String {
        switch self {
        case .tooDemo: "Too Beat Them All"
        default: title
        }
    }

    var artwork: String {
        switch self {
        case .tooDemo: "ArcadeTooIcon"
        default: "ArcadePuzzleIcon"
        }
    }

    var accent: Color {
        switch self {
        case .tooDemo: Color(red: 0.66, green: 0.20, blue: 0.45)
        default: Color(red: 0.43, green: 0.26, blue: 0.73)
        }
    }

    var genre: String {
        switch self {
        case .tooDemo: "Action · Beat ’em up"
        default: "Puzzle · Take your time"
        }
    }

    var explanation: String {
        switch self {
        case .tooDemo: "Join Too for a little street-side mayhem. Jump, bop and swing your spatula through three waves of mischievous enemies."
        default: "A quiet challenge with Too and Tiel. Slide the tiles into the empty space to rebuild the secret lab picture, one move at a time."
        }
    }

    var scope: String {
        switch self {
        case .tooDemo: "Demo · 1 stage · 3 waves"
        default: "Sliding puzzle · A fresh shuffle every time"
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooDemo: "Too Beat Them All · Demo"
        case .puzzle: "Puzzle"
        case .memory: "Memory"
        case .scratch: "Scratch"
        case .labRun: "Lab Run"
        case .flappyTiel: "Flappy"
        case .pong: "Too Pong"
        }
    }

    var subtitle: String {
        switch self {
        case .tooDemo: "One stage. Three waves."
        case .puzzle: "Slide the secret lab scene."
        case .memory: "Match every lab specimen."
        case .scratch: "Experiment not mixed yet."
        case .labRun: "Too and Tiel dodge lab snacks."
        case .flappyTiel: "Tap Tiel through the pipes."
        case .pong: "Too vs Tiel vertical rally."
        }
    }

    var symbol: String {
        switch self {
        case .tooDemo: "figure.boxing"
        case .puzzle: "square.grid.3x3.fill"
        case .memory: "rectangle.on.rectangle.angled"
        case .scratch: "sparkles"
        case .labRun: "figure.run"
        case .flappyTiel: "bird.fill"
        case .pong: "circle.grid.cross.fill"
        }
    }
}

private struct LabArcadeFullscreenGameView: View {
    let game: LabArcadeGame
    var run: ArcadeRun? = nil
    let onBack: () -> Void

    var body: some View {
        switch game {
        case .tooDemo:
            ArcadeDemoView(onBack: onBack, run: run)
        case .puzzle:
            LabSlidingPuzzleCard(onBack: onBack, run: run)
        case .memory:
            LabMemoryGameCard(onBack: onBack)
        case .scratch:
            LabScratchGameCard(onBack: onBack)
        case .labRun:
            LabRunGameCard(onBack: onBack)
        case .flappyTiel:
            FlappyTielGameCard(onBack: onBack)
        case .pong:
            LabPongGameCard()
        }
    }
}

struct LabArcadeBackButton: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))

                Text("Back")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
            }
            .foregroundStyle(FBColors.charcoal)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.white.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.68)))
        }
        .buttonStyle(.plain)
    }
}

private struct LabScratchGameCard: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void
    @State private var symbols = LabScratchTicket.newTicket()
    @State private var revealedBoxes: Set<Int> = []
    @State private var scratchedCellsByBox: [Int: Set<Int>] = [:]
    @State private var completionMessage: String?
    @AppStorage("LabScratchTicketsPlayed") private var ticketsPlayed = 0
    @AppStorage("LabScratchWins") private var wins = 0

    private var dailyRewardAmount: Int {
        appState.tooLabProgress.dailyGameXP
    }

    private var scratchProgress: Double {
        Double(revealedBoxes.count) / Double(symbols.count)
    }

    private var isComplete: Bool {
        revealedBoxes.count == symbols.count
    }

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: LabArcadeGame.scratch.rawValue)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.83, blue: 0.35),
                    Color(red: 0.73, green: 0.34, blue: 0.72),
                    Color(red: 0.15, green: 0.08, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LabArcadeBackButton(onBack: onBack)

                    Spacer()

                    Button("New ticket") {
                        resetTicket()
                    }
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(FBColors.charcoal)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.white.opacity(0.88), in: Capsule())
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Scratch Test")
                        .font(.custom("AvenirNext-DemiBold", size: 26))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(isComplete ? "Ticket checked." : "Find 3 Too or 3 Tiel.")
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    LabPuzzleStatPill(title: "Found", value: "\(revealedBoxes.count)/9")
                    LabPuzzleStatPill(title: "Wins", value: "\(wins)")
                    LabPuzzleStatPill(title: "Daily", value: hasClaimedDailyReward ? "Claimed" : "+\(dailyRewardAmount) LXP")
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(symbols.indices, id: \.self) { index in
                        LabScratchBoxView(
                            symbol: symbols[index],
                            scratchedCells: scratchedCellsByBox[index, default: []],
                            isRevealed: revealedBoxes.contains(index)
                        )
                            .aspectRatio(1, contentMode: .fit)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        scratchBox(at: index, location: value.location)
                                    }
                            )
                            .accessibilityLabel(revealedBoxes.contains(index) ? "\(symbols[index].title) scratch box" : "Hidden scratch box")
                    }
                }
                .padding(12)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.62)))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 9)

                if let completionMessage {
                    HStack(spacing: 8) {
                        Image(systemName: messageIconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(messageTint)

                        Text(completionMessage)
                            .font(.custom("AvenirNext-DemiBold", size: 13))
                            .foregroundStyle(FBColors.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 54)
            .padding(.horizontal, FBSpacing.md)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageIconName: String {
        completionMessage?.contains("WIN") == true ? "checkmark.seal.fill" : "xmark.seal.fill"
    }

    private var messageTint: Color {
        completionMessage?.contains("WIN") == true ? Color.purple : FBColors.muted
    }

    private func scratchBox(at index: Int, location: CGPoint) {
        guard symbols.indices.contains(index),
              !revealedBoxes.contains(index),
              !isComplete else {
            return
        }

        let gridSize = 7
        let boxSize: CGFloat = 110
        let column = min(max(Int(location.x / max(boxSize / CGFloat(gridSize), 1)), 0), gridSize - 1)
        let row = min(max(Int(location.y / max(boxSize / CGFloat(gridSize), 1)), 0), gridSize - 1)
        let before = scratchedCellsByBox[index, default: []].count

        for rowOffset in -1...1 {
            for columnOffset in -1...1 {
                let nextColumn = column + columnOffset
                let nextRow = row + rowOffset
                guard nextColumn >= 0, nextColumn < gridSize, nextRow >= 0, nextRow < gridSize else {
                    continue
                }
                scratchedCellsByBox[index, default: []].insert((nextRow * gridSize) + nextColumn)
            }
        }

        let scratchedCount = scratchedCellsByBox[index, default: []].count

        if scratchedCount > before, scratchedCount % 4 == 0 {
            LabArcadeSound.playScratch()
        }

        if scratchedCount >= 24 {
            revealBox(at: index)
        }
    }

    private func revealBox(at index: Int) {
        guard symbols.indices.contains(index),
              !revealedBoxes.contains(index),
              !isComplete else {
            return
        }

        scratchedCellsByBox[index] = Set(0..<49)
        revealedBoxes.insert(index)
        LabArcadeSound.playReveal()

        if isComplete {
            completeTicket()
        }
    }

    private func completeTicket() {
        ticketsPlayed += 1

        if let winner = LabScratchTicket.winningSymbol(in: symbols) {
            wins += 1
            LabArcadeSound.playSuccess()

            if hasClaimedDailyReward {
                completionMessage = "WIN: 3 \(winner.title). Daily reward already claimed."
            } else {
                completionMessage = "WIN: 3 \(winner.title). Claiming LXP..."
                Task {
                    let awarded = await appState.completeTooLabGame(identifier: LabArcadeGame.scratch.rawValue)
                    completionMessage = awarded > 0 ? "WIN: 3 \(winner.title). Daily +\(awarded) LXP awarded." : "WIN: 3 \(winner.title). Daily reward already claimed."
                }
            }
        } else {
            completionMessage = "No match this time. Too demands a rematch."
        }
    }

    private func resetTicket() {
        symbols = LabScratchTicket.newTicket()
        revealedBoxes = []
        scratchedCellsByBox = [:]
        completionMessage = nil
    }
}

private struct LabScratchBoxView: View {
    let symbol: LabScratchSymbol
    let scratchedCells: Set<Int>
    let isRevealed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)

            Image(symbol.imageName)
                .resizable()
                .scaledToFit()
                .padding(10)
                .opacity(isRevealed || !scratchedCells.isEmpty ? 1 : 0)
                .scaleEffect(isRevealed ? 1 : 0.86)

            if !isRevealed {
                LabScratchBoxFoil(scratchedCells: scratchedCells)
                    .overlay {
                        if scratchedCells.isEmpty {
                            VStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .bold))
                                Text("?")
                                    .font(.custom("AvenirNext-DemiBold", size: 26))
                            }
                            .foregroundStyle(Color.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
                        }
                    }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(FBColors.line.opacity(0.58)))
        .shadow(color: .black.opacity(0.06), radius: 9, y: 5)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isRevealed)
    }
}

private struct LabScratchBoxFoil: View {
    let scratchedCells: Set<Int>

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 18),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.96, green: 0.92, blue: 0.84),
                        Color(red: 0.67, green: 0.61, blue: 0.52),
                        Color(red: 0.93, green: 0.88, blue: 0.78)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            for stripe in 0..<5 {
                let y = CGFloat(stripe) * size.height / 5.0
                var path = Path()
                path.move(to: CGPoint(x: -20, y: y + 10))
                path.addLine(to: CGPoint(x: size.width + 20, y: y - 16))
                context.stroke(path, with: .color(Color.white.opacity(0.18)), lineWidth: 8)
            }

            context.blendMode = .clear
            let gridSize = 7
            for cell in scratchedCells {
                let column = cell % gridSize
                let row = cell / gridSize
                let center = CGPoint(
                    x: (CGFloat(column) + 0.5) * size.width / CGFloat(gridSize),
                    y: (CGFloat(row) + 0.5) * size.height / CGFloat(gridSize)
                )
                let radius = min(size.width, size.height) * 0.145
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.black)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .compositingGroup()
    }
}

private enum LabScratchSymbol: CaseIterable {
    case too
    case tiel
    case burger

    var title: String {
        switch self {
        case .too: "Too"
        case .tiel: "Tiel"
        case .burger: "Burger"
        }
    }

    var imageName: String {
        switch self {
        case .too: "ScratchToo"
        case .tiel: "ScratchTiel"
        case .burger: "ScratchBurger"
        }
    }

    var canWin: Bool {
        switch self {
        case .too, .tiel: true
        case .burger: false
        }
    }
}

private enum LabScratchTicket {
    static func newTicket() -> [LabScratchSymbol] {
        if Int.random(in: 0..<100) < 6 {
            let winner: LabScratchSymbol = Bool.random() ? .too : .tiel
            var symbols = Array(repeating: winner, count: 3)

            while symbols.count < 9 {
                symbols.append([LabScratchSymbol.too, .tiel, .burger].randomElement()!)
            }

            return symbols.shuffled()
        }

        var ticket: [LabScratchSymbol] = []
        var tooCount = 0
        var tielCount = 0

        while ticket.count < 9 {
            let next = [LabScratchSymbol.too, .tiel, .burger].randomElement()!
            if next == .too, tooCount >= 2 { continue }
            if next == .tiel, tielCount >= 2 { continue }

            ticket.append(next)
            if next == .too { tooCount += 1 }
            if next == .tiel { tielCount += 1 }
        }

        return ticket.shuffled()
    }

    static func winningSymbol(in symbols: [LabScratchSymbol]) -> LabScratchSymbol? {
        LabScratchSymbol.allCases.first { symbol in
            symbol.canWin && symbols.filter { $0 == symbol }.count >= 3
        }
    }
}

private struct LabPongGameCard: View {
    @EnvironmentObject private var appState: AppState
    private let winningScore = 3
    private let maximumBallSpeed: CGFloat = 1.18
    private let frameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    @State private var playerX: CGFloat = 0.5
    @State private var tielX: CGFloat = 0.5
    @State private var ballPosition = CGPoint(x: 0.5, y: 0.52)
    @State private var ballVelocity = CGVector(dx: 0.34, dy: -0.52)
    @State private var lastFrameDate: Date?
    @State private var playerScore = 0
    @State private var tielScore = 0
    @State private var rallyHits = 0
    @State private var tielAimError = CGFloat.random(in: -0.08...0.08)
    @State private var isGameOver = false
    @State private var completionMessage: String?

    @AppStorage("LabPongWins") private var wins = 0
    @AppStorage("LabPongBestStreak") private var bestStreak = 0
    @AppStorage("LabPongCurrentStreak") private var currentStreak = 0
    private var dailyRewardAmount: Int {
        appState.tooLabProgress.dailyGameXP
    }

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: LabArcadeGame.pong.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: "circle.grid.cross.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.purple.opacity(0.82))
                            .frame(width: 16, height: 16)

                        Text("LAB GAME")
                            .font(.custom("AvenirNext-DemiBold", size: 11))
                            .tracking(1.7)
                            .foregroundStyle(FBColors.charcoal)
                    }

                    Text("Too Pong")
                        .font(.custom("AvenirNext-DemiBold", size: 20))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(1)

                    Text(isGameOver ? "Experiment logged." : "Drag Too. First to \(winningScore).")
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(FBColors.muted)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Too \(playerScore) - \(tielScore) Tiel")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(FBColors.muted)

                    Button("Reset") {
                        resetMatch()
                    }
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .foregroundStyle(Color.purple)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                LabPuzzleStatPill(title: "Wins", value: "\(wins)")
                LabPuzzleStatPill(title: "Streak", value: "\(currentStreak)")
                LabPuzzleStatPill(title: "Daily", value: hasClaimedDailyReward ? "Claimed" : "+\(dailyRewardAmount) LXP")
            }

            GeometryReader { proxy in
                LabPongFieldView(
                    playerX: playerX,
                    tielX: tielX,
                    ballPosition: ballPosition,
                    playerScore: playerScore,
                    tielScore: tielScore,
                    isGameOver: isGameOver,
                    completionMessage: completionMessage,
                    onDragPlayer: { x in
                        playerX = min(max(x / max(proxy.size.width, 1), 0.14), 0.86)
                    },
                    onPlayAgain: resetMatch
                )
                .onReceive(frameTimer) { date in
                    stepGame(at: date)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(FBColors.line.opacity(0.58)))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        }
        .padding(FBSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .onDisappear {
            lastFrameDate = nil
        }
    }

    private func stepGame(at date: Date) {
        guard !isGameOver else {
            lastFrameDate = date
            return
        }

        guard let lastFrameDate else {
            self.lastFrameDate = date
            return
        }

        let delta = min(max(date.timeIntervalSince(lastFrameDate), 0), 1.0 / 20.0)
        self.lastFrameDate = date

        let currentSpeed = hypot(ballVelocity.dx, ballVelocity.dy)
        let aiReaction = ballVelocity.dy < 0 ? CGFloat(0.48) : CGFloat(0.28)
        let aiSpeed = CGFloat((0.34 + min(currentSpeed, 1.0) * 0.22) * delta)
        let aiTarget = min(max(ballPosition.x + (ballVelocity.dx * aiReaction) + tielAimError, 0.14), 0.86)
        if abs(aiTarget - tielX) <= aiSpeed {
            tielX = aiTarget
        } else {
            tielX += aiTarget > tielX ? aiSpeed : -aiSpeed
        }

        ballPosition.x += ballVelocity.dx * CGFloat(delta)
        ballPosition.y += ballVelocity.dy * CGFloat(delta)

        let ballRadius: CGFloat = 0.052
        if ballPosition.x <= ballRadius {
            ballPosition.x = ballRadius
            ballVelocity.dx = abs(ballVelocity.dx)
            LabArcadeSound.playBounce()
        } else if ballPosition.x >= 1 - ballRadius {
            ballPosition.x = 1 - ballRadius
            ballVelocity.dx = -abs(ballVelocity.dx)
            LabArcadeSound.playBounce()
        }

        handlePaddleCollision()

        if ballPosition.y > 1.05 {
            scorePoint(forPlayer: false)
        } else if ballPosition.y < -0.05 {
            scorePoint(forPlayer: true)
        }
    }

    private func handlePaddleCollision() {
        let paddleHalfWidth: CGFloat = 0.15
        let topPaddleY: CGFloat = 0.14
        let bottomPaddleY: CGFloat = 0.86
        let ballRadius: CGFloat = 0.052

        if ballVelocity.dy > 0,
           ballPosition.y + ballRadius >= bottomPaddleY,
           ballPosition.y < bottomPaddleY,
           abs(ballPosition.x - playerX) <= paddleHalfWidth {
            bounceFromPaddle(centerX: playerX, direction: -1)
        }

        if ballVelocity.dy < 0,
           ballPosition.y - ballRadius <= topPaddleY,
           ballPosition.y > topPaddleY,
           abs(ballPosition.x - tielX) <= paddleHalfWidth {
            bounceFromPaddle(centerX: tielX, direction: 1)
        }
    }

    private func bounceFromPaddle(centerX: CGFloat, direction: CGFloat) {
        let offset = min(max((ballPosition.x - centerX) / 0.15, -1), 1)
        rallyHits += 1
        let speedBoost = min(0.07 + (CGFloat(rallyHits) * 0.012), 0.16)
        let speed = min(hypot(ballVelocity.dx, ballVelocity.dy) + speedBoost, maximumBallSpeed)
        let horizontalInfluence = abs(offset) < 0.12 ? CGFloat.random(in: -0.12...0.12) : offset
        ballVelocity.dx = horizontalInfluence * speed * 0.72
        ballVelocity.dy = direction * max(0.44, speed * 0.82)
        ballPosition.y += direction * 0.018

        if direction < 0 {
            tielAimError = CGFloat.random(in: -0.11...0.11)
        }

        LabArcadeSound.playBounce()
    }

    private func scorePoint(forPlayer playerScored: Bool) {
        LabArcadeSound.playMatch()

        if playerScored {
            playerScore += 1
        } else {
            tielScore += 1
        }

        if playerScore >= winningScore || tielScore >= winningScore {
            completeMatch(playerWon: playerScore >= winningScore)
            return
        }

        resetRally(servingDown: playerScored)
    }

    private func completeMatch(playerWon: Bool) {
        isGameOver = true
        lastFrameDate = nil

        if playerWon {
            wins += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            LabArcadeSound.playSuccess()

            if hasClaimedDailyReward {
                completionMessage = "Too wins. Daily reward already claimed."
            } else {
                completionMessage = "Too wins. Claiming LXP..."
                Task {
                    let awarded = await appState.completeTooLabGame(identifier: LabArcadeGame.pong.rawValue)
                    completionMessage = awarded > 0 ? "Too wins. Daily +\(awarded) LXP awarded." : "Too wins. Daily reward already claimed."
                }
            }
        } else {
            currentStreak = 0
            completionMessage = "Tiel wins this round. Too requests a rematch."
        }
    }

    private func resetMatch() {
        playerScore = 0
        tielScore = 0
        isGameOver = false
        completionMessage = nil
        lastFrameDate = nil
        playerX = 0.5
        tielX = 0.5
        resetRally(servingDown: Bool.random())
    }

    private func resetRally(servingDown: Bool) {
        rallyHits = 0
        tielAimError = CGFloat.random(in: -0.08...0.08)
        ballPosition = CGPoint(x: 0.5, y: 0.52)
        ballVelocity = CGVector(
            dx: CGFloat.random(in: -0.34...0.34),
            dy: servingDown ? 0.58 : -0.58
        )
    }
}

private struct LabPongFieldView: View {
    let playerX: CGFloat
    let tielX: CGFloat
    let ballPosition: CGPoint
    let playerScore: Int
    let tielScore: Int
    let isGameOver: Bool
    let completionMessage: String?
    let onDragPlayer: (CGFloat) -> Void
    let onPlayAgain: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let playerCenter = CGPoint(x: playerX * size.width, y: size.height * 0.86)
            let tielCenter = CGPoint(x: tielX * size.width, y: size.height * 0.14)
            let ballCenter = CGPoint(x: ballPosition.x * size.width, y: ballPosition.y * size.height)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.06, blue: 0.28),
                        Color(red: 0.44, green: 0.13, blue: 0.62),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.94)

                VStack(spacing: 10) {
                    ForEach(0..<14, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.24))
                            .frame(width: 5, height: 15)
                    }
                }

                LabPongScoreBadge(title: "Tiel", score: tielScore)
                    .position(x: size.width - 42, y: 34)

                LabPongScoreBadge(title: "Too", score: playerScore)
                    .position(x: 42, y: size.height - 34)

                LabPongPaddle(center: tielCenter, imageName: "ScratchTiel", tint: Color.purple)
                LabPongPaddle(center: playerCenter, imageName: "ScratchToo", tint: FBColors.caramel)

                Image("ScratchBurger")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
                    .position(ballCenter)

                if isGameOver {
                    VStack(spacing: 10) {
                        Text(completionMessage ?? "Match complete.")
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(FBColors.charcoal)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: onPlayAgain) {
                            Text("Play again")
                                .font(.custom("AvenirNext-DemiBold", size: 13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 38)
                                .background(Color.purple, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(width: min(size.width - 48, 280))
                    .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.72)))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDragPlayer(value.location.x)
                    }
            )
        }
    }
}

private struct LabPongPaddle: View {
    let center: CGPoint
    let imageName: String
    let tint: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(tint)
                .frame(width: 112, height: 18)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .offset(y: 28)

            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 66)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.86), lineWidth: 3))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .position(center)
    }
}

private struct LabPongScoreBadge: View {
    let title: String
    let score: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 9))
                .tracking(0.8)
                .foregroundStyle(FBColors.muted)
                .textCase(.uppercase)

            Text("\(score)")
                .font(.custom("AvenirNext-DemiBold", size: 20))
                .foregroundStyle(FBColors.charcoal)
        }
        .frame(width: 54, height: 48)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.66)))
    }
}

private struct LabMemoryGameCard: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void
    @State private var cards = LabMemoryCard.shuffledDeck()
    @State private var firstSelectedIndex: Int?
    @State private var isCheckingMatch = false
    @State private var attempts = 0
    @State private var completionMessage: String?
    @AppStorage("LabMemoryBestAttempts") private var bestAttempts = 0
    private var dailyRewardAmount: Int {
        appState.tooLabProgress.dailyGameXP
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var isComplete: Bool {
        cards.allSatisfy(\.isMatched)
    }

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: LabArcadeGame.memory.rawValue)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.55, blue: 0.72),
                    Color(red: 0.17, green: 0.12, blue: 0.36),
                    Color(red: 0.95, green: 0.78, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LabArcadeBackButton(onBack: onBack)

                    Spacer()

                    Button("Shuffle") {
                        resetGame()
                    }
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(FBColors.charcoal)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.white.opacity(0.88), in: Capsule())
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Memory Match")
                        .font(.custom("AvenirNext-DemiBold", size: 26))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(isComplete ? "All specimens matched." : "Find every matching pair.")
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    LabPuzzleStatPill(title: "Tries", value: "\(attempts)")
                    LabPuzzleStatPill(title: "Best", value: bestAttempts > 0 ? "\(bestAttempts)" : "--")
                    LabPuzzleStatPill(title: "Daily", value: hasClaimedDailyReward ? "Claimed" : "+\(dailyRewardAmount) LXP")
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(cards.indices, id: \.self) { index in
                        LabMemoryCardView(card: cards[index])
                            .aspectRatio(0.72, contentMode: .fit)
                            .onTapGesture {
                                selectCard(at: index)
                            }
                            .accessibilityLabel(cards[index].isFaceUp || cards[index].isMatched ? "Memory card \(cards[index].title)" : "Hidden memory card")
                    }
                }

                if let completionMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.purple)

                        Text(completionMessage)
                            .font(.custom("AvenirNext-DemiBold", size: 13))
                            .foregroundStyle(FBColors.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 54)
            .padding(.horizontal, FBSpacing.md)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectCard(at index: Int) {
        guard cards.indices.contains(index),
              !isCheckingMatch,
              !cards[index].isFaceUp,
              !cards[index].isMatched,
              !isComplete else {
            return
        }

        LabArcadeSound.playFlip()
        withAnimation(.easeInOut(duration: 0.28)) {
            cards[index].isFaceUp = true
        }

        guard let firstIndex = firstSelectedIndex else {
            firstSelectedIndex = index
            return
        }

        attempts += 1
        firstSelectedIndex = nil

        if cards[firstIndex].matchID == cards[index].matchID {
            LabArcadeSound.playMatch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                guard cards.indices.contains(firstIndex),
                      cards.indices.contains(index) else {
                    return
                }

                cards[firstIndex].isMatched = true
                cards[index].isMatched = true

                if isComplete {
                    completeGame()
                }
            }
        } else {
            isCheckingMatch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
                guard cards.indices.contains(firstIndex),
                      cards.indices.contains(index) else {
                    isCheckingMatch = false
                    return
                }

                withAnimation(.easeInOut(duration: 0.28)) {
                    cards[firstIndex].isFaceUp = false
                    cards[index].isFaceUp = false
                }
                isCheckingMatch = false
            }
        }
    }

    private func completeGame() {
        LabArcadeSound.playSuccess()

        if bestAttempts == 0 || attempts < bestAttempts {
            bestAttempts = attempts
        }

        if hasClaimedDailyReward {
            completionMessage = "Memory complete. Daily reward already claimed."
        } else {
            completionMessage = "Memory complete. Claiming LXP..."
            Task {
                let awarded = await appState.completeTooLabGame(identifier: LabArcadeGame.memory.rawValue, score: attempts)
                completionMessage = awarded > 0 ? "Memory complete. Daily +\(awarded) LXP awarded." : "Memory complete. Daily reward already claimed."
            }
        }
    }

    private func resetGame() {
        cards = LabMemoryCard.shuffledDeck()
        firstSelectedIndex = nil
        isCheckingMatch = false
        attempts = 0
        completionMessage = nil
    }
}

private struct LabMemoryCard: Identifiable {
    let id: Int
    let matchID: Int
    let imageName: String
    let title: String
    var isFaceUp = false
    var isMatched = false

    static func shuffledDeck() -> [LabMemoryCard] {
        let faces = [
            (imageName: "LabMemoryToo", title: "Too"),
            (imageName: "LabMemoryTiel", title: "Tiel"),
            (imageName: "LabMemoryBrownie", title: "Protein Brownie"),
            (imageName: "LabMemoryPotion", title: "Lab Potion"),
            (imageName: "LabMemoryCookie", title: "Streak Cookie")
        ]

        return faces.enumerated().flatMap { index, face in
            [
                LabMemoryCard(id: index * 2, matchID: index, imageName: face.imageName, title: face.title),
                LabMemoryCard(id: index * 2 + 1, matchID: index, imageName: face.imageName, title: face.title)
            ]
        }
        .shuffled()
    }
}

private struct LabMemoryCardView: View {
    let card: LabMemoryCard

    var body: some View {
        ZStack {
            LabMemoryCardFace(imageName: card.imageName)
                .opacity(card.isFaceUp || card.isMatched ? 1 : 0)
                .rotation3DEffect(
                    .degrees(card.isFaceUp || card.isMatched ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0)
                )

            LabMemoryCardBack()
                .opacity(card.isFaceUp || card.isMatched ? 0 : 1)
                .rotation3DEffect(
                    .degrees(card.isFaceUp || card.isMatched ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
        }
        .opacity(card.isMatched ? 0.62 : 1)
        .animation(.easeInOut(duration: 0.28), value: card.isFaceUp)
        .animation(.easeInOut(duration: 0.2), value: card.isMatched)
    }
}

private struct LabMemoryCardFace: View {
    let imageName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(6)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FBColors.line.opacity(0.74)))
    }
}

private struct LabMemoryCardBack: View {
    var body: some View {
        Image("LabMemoryCardBack")
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FBColors.line.opacity(0.74)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

private struct LabArcadeComingSoonCard: View {
    let game: LabArcadeGame

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: game.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.purple.opacity(0.72))
                .frame(width: 48, height: 48)
                .background(FBColors.card, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(game.title) Lab")
                    .font(.custom("AvenirNext-DemiBold", size: 18))
                    .foregroundStyle(FBColors.charcoal)
                Text("Experiment not mixed yet.")
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(FBColors.muted)
            }

            Spacer()
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.66)))
    }
}

private struct LabSlidingPuzzleCard: View {
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void
    var run: ArcadeRun? = nil
    @State private var moveLog: [Int] = []
    @State private var rewardDeadline: ContinuousClock.Instant?
    @State private var retryReward = false
    @State private var claimingReward = false
    private let gridSize = 3
    @State private var tiles: [Int?] = LabSlidingPuzzleCard.solvedTiles
    @State private var moves = 0
    @State private var hasCompletedCurrentPuzzle = false
    @State private var completionMessage: String?
    @AppStorage("LabPuzzleBestMoves") private var bestMoves = 0

    private static let solvedTiles: [Int?] = Array(0..<8).map(Optional.some) + [nil]

    private var isSolved: Bool {
        tiles == Self.solvedTiles
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.72, blue: 0.24),
                    Color(red: 0.16, green: 0.62, blue: 0.73),
                    Color(red: 0.12, green: 0.14, blue: 0.28)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LabArcadeBackButton(onBack: onBack)

                    Spacer()

                    Button("New game") { onBack() }
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(FBColors.charcoal)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.white.opacity(0.88), in: Capsule())
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Secret Lab Puzzle")
                        .font(.custom("AvenirNext-DemiBold", size: 26))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(isSolved ? "Experiment complete." : "Slide one tile at a time.")
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    LabPuzzleStatPill(title: "Moves", value: "\(moves)")
                    LabPuzzleStatPill(title: "Best", value: bestMoves > 0 ? "\(bestMoves)" : "--")
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        let remaining = rewardDeadline.map { max(0, Int(ceil(Double(ContinuousClock.now.duration(to: $0).components.seconds) + Double(ContinuousClock.now.duration(to: $0).components.attoseconds) / 1e18))) } ?? 0
                        LabPuzzleStatPill(title: "Rico", value: hasCompletedCurrentPuzzle ? "Finished" : "\(remaining)s")
                    }
                }

                GeometryReader { proxy in
                    let boardSize = min(proxy.size.width, proxy.size.height)
                    let tileSpacing: CGFloat = 2
                    let tileSize = (boardSize - (CGFloat(gridSize - 1) * tileSpacing)) / CGFloat(gridSize)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)

                        ForEach(tiles.indices, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(tiles[index] == nil ? 0.86 : 0.38))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(FBColors.line.opacity(0.42))
                                }
                                .frame(width: tileSize, height: tileSize)
                                .position(cellPosition(for: index, tileSize: tileSize, spacing: tileSpacing))
                        }

                        ForEach(0..<(gridSize * gridSize - 1), id: \.self) { tile in
                            if let index = tiles.firstIndex(where: { $0 == Optional(tile) }) {
                                PuzzleTile(
                                    imageName: "TooLabHomeCard",
                                    tile: tile,
                                    gridSize: gridSize,
                                    tileSize: tileSize
                                )
                                .frame(width: tileSize, height: tileSize)
                                .position(cellPosition(for: index, tileSize: tileSize, spacing: tileSpacing))
                                .accessibilityLabel("Puzzle tile \(tile + 1)")
                            }
                        }
                    }
                    .frame(width: boardSize, height: boardSize)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let boardOrigin = CGPoint(
                                    x: (proxy.size.width - boardSize) / 2,
                                    y: (proxy.size.height - boardSize) / 2
                                )
                                moveTile(
                                    at: CGPoint(x: value.location.x - boardOrigin.x, y: value.location.y - boardOrigin.y),
                                    tileSize: tileSize,
                                    spacing: tileSpacing
                                )
                            }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if retryReward {
                    Button("Retry reward sync") { Task { await claimReward() } }
                        .disabled(claimingReward)
                }
                if let completionMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.purple)

                        Text(completionMessage)
                            .font(.custom("AvenirNext-DemiBold", size: 13))
                            .foregroundStyle(FBColors.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.top, 54)
            .padding(.horizontal, FBSpacing.md)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard rewardDeadline == nil else { return }
            if let run, let board = run.board, board.count == 9 {
                tiles = board.map { $0 == 8 ? nil : $0 }
                rewardDeadline = run.rewardDeadline
            } else {
                completionMessage = "Start a new game from My Arcade to play."
                hasCompletedCurrentPuzzle = true
            }
        }
    }


    private func moveTile(at location: CGPoint, tileSize: CGFloat, spacing: CGFloat) {
        guard !hasCompletedCurrentPuzzle else {
            return
        }

        let stride = tileSize + spacing
        let column = min(max(Int(location.x / stride), 0), gridSize - 1)
        let row = min(max(Int(location.y / stride), 0), gridSize - 1)
        let index = (row * gridSize) + column

        guard index >= 0,
              index < tiles.count,
              tiles[index] != nil else {
            return
        }

        guard let blank = tiles.firstIndex(where: { $0 == nil }),
              isAdjacent(index, blank) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            tiles.swapAt(index, blank)
        }
        LabPuzzleSound.playMove()
        moves += 1
        moveLog.append(index)

        if isSolved {
            completePuzzle()
        }
    }

    private func cellPosition(for index: Int, tileSize: CGFloat, spacing: CGFloat) -> CGPoint {
        let row = index / gridSize
        let column = index % gridSize
        let stride = tileSize + spacing

        return CGPoint(
            x: (CGFloat(column) * stride) + tileSize / 2,
            y: (CGFloat(row) * stride) + tileSize / 2
        )
    }

    private func completePuzzle() {
        hasCompletedCurrentPuzzle = true
        LabPuzzleSound.playSuccess()

        if bestMoves == 0 || moves < bestMoves {
            bestMoves = moves
        }

        Task { await claimReward() }
    }

    @MainActor
    private func claimReward() async {
        guard let run, !claimingReward else { return }
        claimingReward = true; retryReward = false
        completionMessage = "Checking your Rico reward…"
        defer { claimingReward = false }
        do {
            completionMessage = try await appState.finishArcadeRun(id: run.id, result: ArcadeCompletion(moves: moveLog))
        } catch {
            completionMessage = "Reward not synced. Please retry."
            retryReward = true
        }
    }

    private func isAdjacent(_ lhs: Int, _ rhs: Int) -> Bool {
        adjacentIndices(to: lhs).contains(rhs)
    }

    private func adjacentIndices(to index: Int) -> [Int] {
        let row = index / gridSize
        let column = index % gridSize
        var indices: [Int] = []

        if row > 0 { indices.append(index - gridSize) }
        if row < gridSize - 1 { indices.append(index + gridSize) }
        if column > 0 { indices.append(index - 1) }
        if column < gridSize - 1 { indices.append(index + 1) }

        return indices
    }
}

struct LabPuzzleStatPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 10))
                .tracking(1.0)
                .foregroundStyle(FBColors.muted)
                .textCase(.uppercase)

            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(FBColors.charcoal)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(FBColors.card, in: Capsule())
        .overlay(Capsule().stroke(FBColors.line.opacity(0.5)))
    }
}

private enum LabPuzzleSound {
    static func playMove() {
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func playSuccess() {
        AudioServicesPlaySystemSound(1025)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum LabArcadeSound {
    static func playBounce() {
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func playScratch() {
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func playReveal() {
        AudioServicesPlaySystemSound(1105)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func playFlip() {
        AudioServicesPlaySystemSound(1105)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func playMatch() {
        AudioServicesPlaySystemSound(1057)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func playSuccess() {
        AudioServicesPlaySystemSound(1025)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct PuzzleTile: View {
    let imageName: String
    let tile: Int
    let gridSize: Int
    let tileSize: CGFloat

    private var row: Int {
        tile / gridSize
    }

    private var column: Int {
        tile % gridSize
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: tileSize * CGFloat(gridSize), height: tileSize * CGFloat(gridSize))
            .offset(
                x: CGFloat(gridSize - 1) * tileSize / 2 - CGFloat(column) * tileSize,
                y: CGFloat(gridSize - 1) * tileSize / 2 - CGFloat(row) * tileSize
            )
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7), lineWidth: 1))
            .clipped()
    }
}

private struct LabPrivilegeRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isLocked ? FBColors.muted : FBColors.cookieOrange)
                .frame(width: 38, height: 38)
                .background(FBColors.surface, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .tracking(1.0)
                    .foregroundStyle(FBColors.charcoal)
                Text(subtitle)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .tracking(0.45)
                    .foregroundStyle(FBColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: isLocked ? "lock" : "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isLocked ? FBColors.muted : .white)
                .frame(width: 28, height: 28)
                .background(isLocked ? Color.clear : FBColors.cookieOrange, in: Circle())
                .overlay(Circle().stroke(isLocked ? FBColors.line.opacity(0.72) : Color.clear))
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.55)))
    }
}
