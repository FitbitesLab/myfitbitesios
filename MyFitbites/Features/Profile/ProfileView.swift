import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let showsBackButton: Bool
    @State private var editingAddress: SavedAddress?
    @State private var isAccountEditorPresented = false
    @State private var isAvatarPickerPresented = false
    @State private var isDefaultAddressPickerPresented = false
    @State private var isLogoutConfirmationPresented = false
    @State private var isLoggingOut = false
    @State private var editingPreference: AccountPreferenceSheet?
    @AppStorage("myfitbites.preference.preferred-order") private var preferredOrderPreference = "Pick up first"
    @AppStorage("myfitbites.preference.notifications") private var notificationsPreference = "Rewards and order status"

    init(showsBackButton: Bool = false) {
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                if showsBackButton {
                    backButton
                }

                profileHeader
                accountCard
                myFitbitesCard
                addressCard
                preferencesCard
            }
            .padding(FBSpacing.md)
            .padding(.bottom, FBSpacing.xl)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Account")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingAddress) { address in
            AddressEditorSheet(address: address) { updatedAddress in
                if let index = appState.savedAddresses.firstIndex(where: { $0.id == updatedAddress.id }) {
                    appState.savedAddresses[index] = updatedAddress
                    appState.selectedAddressID = updatedAddress.id
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAvatarPickerPresented) {
            AccountAvatarPickerSheet(avatar: appState.customerProfile.avatar) { avatar in
                appState.updateLocalAvatar(avatar)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAccountEditorPresented) {
            AccountDetailsEditorSheet(profile: appState.customerProfile) { name, phone, email, currentPassword, newPassword in
                try await appState.updateCustomerAccount(
                    name: name,
                    phone: phone,
                    email: email,
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isDefaultAddressPickerPresented) {
            DefaultAddressPickerSheet(
                addresses: appState.savedAddresses,
                selectedAddressID: appState.selectedAddressID
            ) { address in
                appState.selectSavedAddress(address)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingPreference) { preference in
            AccountPreferencePickerSheet(
                preference: preference,
                preferredOrder: $preferredOrderPreference,
                notifications: $notificationsPreference
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Log out?", isPresented: $isLogoutConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Log out", role: .destructive) {
                Task {
                    await logOut()
                }
            }
        } message: {
            Text("You'll need to sign in again to use your MyFitbites account on this device.")
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(FBColors.charcoal)
                .frame(width: 44, height: 44)
                .background(FBColors.surface, in: Circle())
                .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            Button {
                isAvatarPickerPresented = true
            } label: {
                FBAvatarView(avatar: appState.customerProfile.avatar, size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(FBColors.cookieOrange, in: Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change avatar")

            VStack(alignment: .leading, spacing: 5) {
                Text("Account settings")
                    .font(.custom("AvenirNext-DemiBold", size: 18))
                    .tracking(0.75)
                    .foregroundStyle(FBColors.charcoal)
                Text("Profile, addresses and delivery preferences.")
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .tracking(0.55)
                    .foregroundStyle(FBColors.muted)
            }
        }
        .padding(.top, 10)
    }

    private var accountCard: some View {
        SettingsCard(title: "Account") {
            SettingsAvatarRow(
                avatar: appState.customerProfile.avatar,
                title: "Avatar",
                value: LocalAvatarPreset.preset(for: appState.customerProfile.avatar.presetID).name
            ) {
                isAvatarPickerPresented = true
            }
            SettingsDivider()
            SettingsInfoRow(label: "Name", value: appState.customerProfile.name, symbol: "person") {
                isAccountEditorPresented = true
            }
            SettingsDivider()
            SettingsInfoRow(label: "Phone", value: appState.customerProfile.phone, symbol: "phone") {
                isAccountEditorPresented = true
            }
            SettingsDivider()
            SettingsInfoRow(label: "eMail", value: appState.customerProfile.email, symbol: "envelope") {
                isAccountEditorPresented = true
            }
            SettingsDivider()
            SettingsInfoRow(label: "Password", value: "••••••••", symbol: "lock") {
                isAccountEditorPresented = true
            }
            SettingsDivider()
            SettingsActionRow(
                title: isLoggingOut ? "Logging out" : "Log out",
                symbol: "rectangle.portrait.and.arrow.right",
                role: .destructive,
                isDisabled: isLoggingOut
            ) {
                isLogoutConfirmationPresented = true
            }
        }
    }

    private var addressCard: some View {
        SettingsCard(title: "Address") {
            ForEach(Array(appState.savedAddresses.enumerated()), id: \.element.id) { index, address in
                AddressSettingsRow(
                    address: address,
                    isSelected: address.id == appState.selectedAddressID,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appState.selectSavedAddress(address)
                        }
                    },
                    onEdit: {
                        editingAddress = address
                    }
                )

                if index < appState.savedAddresses.count - 1 {
                    SettingsDivider()
                }
            }
        }
    }

    private var myFitbitesCard: some View {
        SettingsCard(title: "My Fitbites") {
            NavigationLink {
                MyOrdersView()
                    .environmentObject(appState)
            } label: {
                SettingsNavigationRow(
                    label: "My Orders",
                    value: ordersSummary,
                    symbol: "list.bullet.clipboard"
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink {
                AccountAchievementsView()
                    .environmentObject(appState)
            } label: {
                SettingsNavigationRow(
                    label: "Achievements",
                    value: achievementsSummary,
                    symbol: "medal"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var preferencesCard: some View {
        SettingsCard(title: "Preferences") {
            SettingsInfoRow(label: "Default delivery", value: selectedAddressLabel, symbol: "location") {
                isDefaultAddressPickerPresented = true
            }
            SettingsDivider()
            SettingsInfoRow(label: "Preferred order", value: preferredOrderPreference, symbol: "bag") {
                editingPreference = .preferredOrder
            }
            SettingsDivider()
            SettingsInfoRow(label: "Notifications", value: notificationsPreference, symbol: "bell") {
                editingPreference = .notifications
            }
        }
    }

    private var selectedAddressLabel: String {
        appState.savedAddresses.first { $0.id == appState.selectedAddressID }?.label ?? "Home"
    }

    private var ordersSummary: String {
        let dashboard = appState.dashboardRepository.dashboard()
        if dashboard.activeOrders.count > 0 {
            return "\(dashboard.activeOrders.count) active"
        }
        if dashboard.pastOrders.count > 0 {
            return "\(dashboard.pastOrders.count) past"
        }
        return "No orders yet"
    }

    private var achievementsSummary: String {
        let achievements = appState.rewardsRepository.rewards().achievements
        let unlocked = achievements.filter(\.isUnlocked).count
        return achievements.isEmpty ? "No badges yet" : "\(unlocked)/\(achievements.count) unlocked"
    }

    @MainActor
    private func logOut() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        defer { isLoggingOut = false }
        await appState.signOut()
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .tracking(1.55)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.charcoal)
                .padding(.horizontal, FBSpacing.md)
                .padding(.top, FBSpacing.md)
                .padding(.bottom, 8)

            content
        }
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.62)))
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FBColors.cookieOrange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.custom("AvenirNext-Regular", size: 10))
                        .tracking(1.25)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.muted)
                    Text(value.isEmpty ? "Add" : value)
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .tracking(0.45)
                        .foregroundStyle(value.isEmpty ? FBColors.cookieOrange : FBColors.charcoal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FBColors.muted.opacity(0.72))
            }
            .padding(.horizontal, FBSpacing.md)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsNavigationRow: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FBColors.cookieOrange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.custom("AvenirNext-Regular", size: 10))
                    .tracking(1.25)
                    .textCase(.uppercase)
                    .foregroundStyle(FBColors.muted)
                Text(value)
                    .font(.custom("AvenirNext-Regular", size: 14))
                    .tracking(0.45)
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FBColors.muted.opacity(0.72))
        }
        .padding(.horizontal, FBSpacing.md)
        .frame(height: 58)
    }
}

private struct SettingsAvatarRow: View {
    let avatar: LocalAvatar
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FBAvatarView(avatar: avatar, size: 38)
                    .frame(width: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("AvenirNext-Regular", size: 10))
                        .tracking(1.25)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.muted)
                    Text(value)
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .tracking(0.45)
                        .foregroundStyle(FBColors.charcoal)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FBColors.muted.opacity(0.72))
            }
            .padding(.horizontal, FBSpacing.md)
            .frame(height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose avatar")
    }
}

private struct SettingsActionRow: View {
    let title: String
    let symbol: String
    var role: ButtonRole?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(role == .destructive ? Color.red.opacity(0.86) : FBColors.cookieOrange)
                    .frame(width: 28)

                Text(title)
                    .font(.custom("AvenirNext-Regular", size: 14))
                    .tracking(0.5)
                    .foregroundStyle(role == .destructive ? Color.red.opacity(0.92) : FBColors.charcoal)

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FBColors.muted.opacity(0.72))
            }
            .padding(.horizontal, FBSpacing.md)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.58 : 1)
    }
}

private struct MyOrdersView: View {
    @EnvironmentObject private var appState: AppState

    private var dashboard: CustomerDashboard {
        appState.dashboardRepository.dashboard()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                if dashboard.activeOrders.isEmpty && dashboard.pastOrders.isEmpty {
                    AccountEmptyState(
                        symbol: "bag",
                        title: "No orders yet",
                        message: "Your active and past Fitbites orders will appear here."
                    )
                } else {
                    if !dashboard.activeOrders.isEmpty {
                        orderSection(title: "Current order", orders: dashboard.activeOrders)
                    }

                    if !dashboard.pastOrders.isEmpty {
                        orderSection(title: "Previous orders", orders: dashboard.pastOrders)
                    }
                }
            }
            .padding(FBSpacing.md)
            .padding(.bottom, FBSpacing.xl)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("My Orders")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await appState.refreshDashboardAndRewards()
        }
    }

    private func orderSection(title: String, orders: [CustomerOrderSummary]) -> some View {
        SettingsCard(title: title) {
            ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                CustomerOrderRow(order: order)

                if index < orders.count - 1 {
                    SettingsDivider()
                }
            }
        }
    }
}

private struct CustomerOrderRow: View {
    let order: CustomerOrderSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Order #\(order.id)")
                        .font(.custom("AvenirNext-DemiBold", size: 15))
                        .foregroundStyle(FBColors.charcoal)
                    Text(order.items)
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .tracking(0.55)
                        .foregroundStyle(FBColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(order.statusLabel.uppercased())
                    .font(.custom("AvenirNext-DemiBold", size: 10))
                    .tracking(0.9)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(statusColor.opacity(0.10), in: Capsule())
            }

            Text(order.statusCopy)
                .font(.custom("AvenirNext-Regular", size: 12))
                .tracking(0.45)
                .foregroundStyle(FBColors.charcoal.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            if !order.lineItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(order.lineItems) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(item.quantity)x \(item.name)")
                                Spacer()
                                if let total = item.total {
                                    Text(total)
                                }
                            }
                            .font(.custom("AvenirNext-Regular", size: 12))
                            .tracking(0.45)
                            .foregroundStyle(FBColors.charcoal)

                            if !item.toppings.isEmpty {
                                Text(item.toppings.joined(separator: ", "))
                                    .font(.custom("AvenirNext-Regular", size: 11))
                                    .tracking(0.65)
                                    .foregroundStyle(FBColors.muted)
                            }
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                if let time = order.time {
                    OrderMetaRow(label: "Time", value: time)
                }
                if let address = order.deliveryAddress {
                    OrderMetaRow(label: "Address", value: address)
                } else if let pickup = order.pickupScheduledAt {
                    OrderMetaRow(label: "Pickup", value: pickup)
                }
                if let payment = order.paymentMethod {
                    OrderMetaRow(label: "Payment", value: payment.replacingOccurrences(of: "_", with: " "))
                }
                OrderMetaRow(label: order.totalLabel, value: order.total)
            }
        }
        .padding(FBSpacing.md)
    }

    private var statusColor: Color {
        switch order.status.lowercased() {
        case "completed", "ready":
            return FBColors.cookieOrange
        case "cancelled", "rejected":
            return .red.opacity(0.82)
        case "preparing", "accepted", "pending", "submitted":
            return FBColors.caramel
        default:
            return FBColors.muted
        }
    }
}

private struct OrderMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.custom("AvenirNext-Regular", size: 12))
                .tracking(0.35)
                .foregroundStyle(FBColors.charcoal)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct AccountAchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private var achievements: [Achievement] {
        Array(appState.rewardsRepository.rewards().achievements.actionableAchievementQueue.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(FBColors.charcoal)
                            .frame(width: 42, height: 42)
                            .background(FBColors.surface, in: Circle())
                            .overlay(Circle().stroke(FBColors.line.opacity(0.65)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()
                }

                if achievements.isEmpty {
                    AccountEmptyState(
                        symbol: "medal",
                        title: "No achievements yet",
                        message: "Complete orders and challenges to unlock Fitbites milestones."
                    )
                } else {
                    SettingsCard(title: "Achievements") {
                        ForEach(Array(achievements.enumerated()), id: \.element.id) { index, achievement in
                            AchievementProgressRow(achievement: achievement)

                            if index < achievements.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
            .padding(FBSpacing.md)
            .padding(.bottom, FBSpacing.xl)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Achievements")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await appState.refreshDashboardAndRewards()
        }
    }
}

private struct AchievementProgressRow: View {
    let achievement: Achievement

    private var progress: Double {
        guard let progress = achievement.progress, let target = achievement.target, target > 0 else {
            return achievement.isUnlocked ? 1 : 0
        }

        return min(1, max(0, Double(progress) / Double(target)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("AchievementTrophy")
                .resizable()
                .scaledToFit()
                .opacity(0.5)
                .padding(5)
                .frame(width: 38, height: 38)
                .background((achievement.isUnlocked ? FBColors.cookieOrange : FBColors.line).opacity(0.10), in: Circle())
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(achievement.title)
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .foregroundStyle(FBColors.charcoal)
                    Spacer()
                    Text(achievement.status.uppercased())
                        .font(.custom("AvenirNext-DemiBold", size: 9))
                        .tracking(0.9)
                        .foregroundStyle(achievement.isUnlocked ? FBColors.cookieOrange : FBColors.muted)
                }

                Text(achievement.subtitle)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .tracking(0.45)
                    .foregroundStyle(FBColors.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(value: progress)
                    .tint(achievement.isUnlocked ? FBColors.cookieOrange : FBColors.muted)

                HStack {
                    if let progress = achievement.progress, let target = achievement.target {
                        Text("\(progress)/\(target)")
                    } else {
                        Text(achievement.tier ?? "Milestone")
                    }

                    Spacer()

                    if let xp = achievement.xpReward {
                        Text("+\(xp) XP")
                    }
                }
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(0.95)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
            }
        }
        .padding(FBSpacing.md)
    }
}

private struct AccountEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(FBColors.cookieOrange)
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 17))
                .foregroundStyle(FBColors.charcoal)
            Text(message)
                .font(.custom("AvenirNext-Regular", size: 12))
                .tracking(0.55)
                .foregroundStyle(FBColors.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.62)))
    }
}

private enum AccountPreferenceSheet: String, Identifiable {
    case preferredOrder
    case notifications

    var id: String { rawValue }
}

private struct AccountDetailsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String, String, String, String) async throws -> Void

    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        profile: CustomerProfile,
        onSave: @escaping (String, String, String, String, String) async throws -> Void
    ) {
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _phone = State(initialValue: profile.phone)
        _email = State(initialValue: profile.email)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                SheetHeader(title: "Edit account") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 12) {
                    AccountEditField(title: "Name", text: $name, prompt: "Your name")
                    AccountEditField(title: "Phone", text: $phone, prompt: "Phone number", keyboardType: .phonePad)
                    AccountEditField(title: "Email", text: $email, prompt: "Email address", keyboardType: .emailAddress)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Password")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .tracking(1.15)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.charcoal)

                    SecureAccountField(title: "Current password", text: $currentPassword, prompt: "Required to change password")
                    SecureAccountField(title: "New password", text: $newPassword, prompt: "Leave empty to keep current password")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .tracking(0.35)
                        .foregroundStyle(.red.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await save() }
                } label: {
                    ZStack {
                        Text(isSaving ? "Saving..." : "Save account")
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                            .tracking(1.2)
                            .textCase(.uppercase)

                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, FBSpacing.lg)
                    .frame(height: 58)
                    .background(canSave ? FBColors.cookieOrange : FBColors.cookieOrange.opacity(0.34), in: RoundedRectangle(cornerRadius: FBCorner.card))
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
            }
            .padding(FBSpacing.md)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard canSave else { return }
        errorMessage = nil

        if !newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Enter your current password to change it."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(name, phone, email, currentPassword, newPassword)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DefaultAddressPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let addresses: [SavedAddress]
    let selectedAddressID: String
    let onSelect: (SavedAddress) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FBSpacing.lg) {
            SheetHeader(title: "Default delivery") {
                dismiss()
            }

            VStack(spacing: 0) {
                ForEach(Array(addresses.enumerated()), id: \.element.id) { index, address in
                    Button {
                        onSelect(address)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(address.label)
                                    .font(.custom("AvenirNext-DemiBold", size: 14))
                                    .tracking(0.45)
                                    .foregroundStyle(FBColors.charcoal)
                                Text(address.detail)
                                    .font(.custom("AvenirNext-Regular", size: 12))
                                    .tracking(0.35)
                                    .foregroundStyle(FBColors.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Spacer()

                            if address.id == selectedAddressID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(FBColors.cookieOrange)
                            }
                        }
                        .padding(.horizontal, FBSpacing.md)
                        .frame(height: 62)
                    }
                    .buttonStyle(.plain)

                    if index < addresses.count - 1 {
                        SettingsDivider()
                    }
                }
            }
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.62)))

            Spacer(minLength: 0)
        }
        .padding(FBSpacing.md)
        .background(Color.white.ignoresSafeArea())
    }
}

private struct AccountPreferencePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preference: AccountPreferenceSheet
    @Binding var preferredOrder: String
    @Binding var notifications: String

    private var title: String {
        switch preference {
        case .preferredOrder:
            return "Preferred order"
        case .notifications:
            return "Notifications"
        }
    }

    private var options: [String] {
        switch preference {
        case .preferredOrder:
            return ["Pick up first", "Delivery first"]
        case .notifications:
            return ["Rewards and order status", "Order status only", "Off"]
        }
    }

    private var selectedValue: String {
        switch preference {
        case .preferredOrder:
            return preferredOrder
        case .notifications:
            return notifications
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FBSpacing.lg) {
            SheetHeader(title: title) {
                dismiss()
            }

            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    Button {
                        select(option)
                        dismiss()
                    } label: {
                        HStack {
                            Text(option)
                                .font(.custom("AvenirNext-Regular", size: 15))
                                .tracking(0.35)
                                .foregroundStyle(FBColors.charcoal)

                            Spacer()

                            if option == selectedValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(FBColors.cookieOrange)
                            }
                        }
                        .padding(.horizontal, FBSpacing.md)
                        .frame(height: 58)
                    }
                    .buttonStyle(.plain)

                    if index < options.count - 1 {
                        SettingsDivider()
                    }
                }
            }
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.62)))

            Spacer(minLength: 0)
        }
        .padding(FBSpacing.md)
        .background(Color.white.ignoresSafeArea())
    }

    private func select(_ option: String) {
        switch preference {
        case .preferredOrder:
            preferredOrder = option
        case .notifications:
            notifications = option
        }
    }
}

private struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 24))
                .foregroundStyle(FBColors.charcoal)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FBColors.charcoal)
                    .frame(width: 42, height: 42)
                    .background(FBColors.surface, in: Circle())
                    .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AccountEditField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(1.25)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
            TextField(prompt, text: $text)
                .font(.custom("AvenirNext-Regular", size: 15))
                .tracking(0.35)
                .foregroundStyle(FBColors.charcoal)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboardType == .emailAddress)
                .padding(13)
                .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.compact))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.62)))
        }
    }
}

private struct SecureAccountField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(1.25)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
            SecureField(prompt, text: $text)
                .font(.custom("AvenirNext-Regular", size: 15))
                .tracking(0.35)
                .foregroundStyle(FBColors.charcoal)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(13)
                .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.compact))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.62)))
        }
    }
}

private struct AccountAvatarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var avatar: LocalAvatar
    let onSave: (LocalAvatar) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(avatar: LocalAvatar, onSave: @escaping (LocalAvatar) -> Void) {
        _avatar = State(initialValue: avatar.customPhotoData == nil ? avatar : LocalAvatar.default)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FBSpacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose avatar")
                        .font(.custom("AvenirNext-DemiBold", size: 24))
                        .foregroundStyle(FBColors.charcoal)

                    Text("Pick a Fitbites universe face.")
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(FBColors.muted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FBColors.charcoal)
                        .frame(width: 42, height: 42)
                        .background(FBColors.surface, in: Circle())
                        .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(LocalAvatarPreset.all) { preset in
                    AccountAvatarOption(
                        preset: preset,
                        isSelected: avatar.presetID == preset.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            avatar = LocalAvatar(presetID: preset.id, customPhotoData: nil)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            FBPrimaryButton(title: "Save avatar", systemImage: "checkmark") {
                onSave(avatar)
                dismiss()
            }
        }
        .padding(FBSpacing.md)
        .background(Color.white.ignoresSafeArea())
    }
}

private struct AccountAvatarOption: View {
    let preset: LocalAvatarPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                FBAvatarView(
                    avatar: LocalAvatar(presetID: preset.id, customPhotoData: nil),
                    size: 78
                )

                Text(preset.name)
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .tracking(0.5)
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? FBColors.card : FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(
                RoundedRectangle(cornerRadius: FBCorner.card)
                    .stroke(isSelected ? FBColors.cookieOrange : FBColors.line.opacity(0.62), lineWidth: isSelected ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(FBColors.cookieOrange)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(preset.name)")
    }
}

private struct AddressSettingsRow: View {
    let address: SavedAddress
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: address.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .white : FBColors.cookieOrange)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? FBColors.cookieOrange : FBColors.cookieOrange.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(address.label) as default address")

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(address.label)
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .tracking(0.85)
                        .foregroundStyle(FBColors.charcoal)
                    Text(address.detail.isEmpty ? "Enter delivery address" : address.detail)
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .tracking(0.35)
                        .foregroundStyle(address.detail.isEmpty ? FBColors.cookieOrange : FBColors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(address.note.isEmpty ? "Add delivery notes" : address.note)
                        .font(.custom("AvenirNext-Regular", size: 10))
                        .tracking(0.35)
                        .foregroundStyle(FBColors.muted.opacity(0.78))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(address.label) address")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FBColors.cookieOrange)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(FBColors.line.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(address.label)")

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? FBColors.cookieOrange : FBColors.line)
        }
        .padding(.horizontal, FBSpacing.md)
        .frame(height: 76)
        .background(isSelected ? Color.white.opacity(0.72) : Color.clear)
        .accessibilityLabel("\(address.label) address")
    }
}

private struct AddressEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let address: SavedAddress
    let onSave: (SavedAddress) -> Void

    @State private var label: String
    @State private var detail: String
    @State private var apartmentUnit: String
    @State private var note: String

    init(address: SavedAddress, onSave: @escaping (SavedAddress) -> Void) {
        self.address = address
        self.onSave = onSave
        _label = State(initialValue: address.label)
        _detail = State(initialValue: address.detail)
        _apartmentUnit = State(initialValue: address.apartmentUnit ?? "")
        _note = State(initialValue: address.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FBSpacing.lg) {
            HStack(alignment: .top) {
                Spacer()

                Button("Done") { dismiss() }
                    .font(.custom("AvenirNext-Regular", size: 16))
                    .foregroundStyle(FBColors.cookieOrange)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(FBColors.surface, in: Capsule())
            }
            .padding(.top, -4)

            HStack(spacing: 12) {
                Image(systemName: address.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(FBColors.cookieOrange, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(address.label)
                        .font(.custom("AvenirNext-DemiBold", size: 16))
                        .tracking(0.7)
                        .foregroundStyle(FBColors.charcoal)
                    Text(address.isConfirmedForDelivery ? "Confirmed delivery address." : "Address details.")
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .tracking(0.45)
                        .foregroundStyle(FBColors.muted)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                AddressTextField(title: "Label", text: $label, prompt: "Home, Office, Studio")
                AddressTextField(title: "Address", text: $detail, prompt: "Street, building, district")
                AddressTextField(title: "Apartment", text: $apartmentUnit, prompt: "Unit, floor, gate")
                AddressTextField(title: "Delivery note", text: $note, prompt: "Gate code, reception, timing")
            }

            Spacer()

            FBPrimaryButton(title: "Save address", systemImage: "checkmark") {
                var updatedAddress = address
                let cleanApartment = apartmentUnit.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedAddress.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedAddress.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedAddress.apartmentUnit = cleanApartment.isEmpty ? nil : cleanApartment
                updatedAddress.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(updatedAddress)
                dismiss()
            }
        }
        .padding(FBSpacing.md)
        .background(Color.white.ignoresSafeArea())
    }
}

private struct AddressTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(1.25)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
            TextField(prompt, text: $text, axis: .vertical)
                .font(.custom("AvenirNext-Regular", size: 14))
                .tracking(0.35)
                .foregroundStyle(FBColors.charcoal)
                .lineLimit(2...4)
                .padding(12)
                .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.compact))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.62)))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(FBColors.line.opacity(0.62))
            .padding(.leading, 56)
    }
}
