import CryptoKit
import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotBridge {
    static let shared = WidgetSnapshotBridge()
    private let store = WidgetSnapshotStore()
    private var session: WidgetSnapshotSession
    private var dashboard: CustomerV2DashboardPayload?
    private var catalog: StoreCatalog?
    private var labPayload: CustomerV2TooLabPayload?
    private var reloadTask: Task<Void, Never>?
    var ticket: UUID { session.generation }
    var snapshot: WidgetSnapshot { session.snapshot }

    private init() { session = WidgetSnapshotSession(snapshot: store.read()) }

    func begin(userID: Int) {
        let key = SHA256.hash(data: Data("myfitbites-widget-account:\(userID)".utf8)).map { String(format: "%02x", $0) }.joined()
        if session.snapshot.accountKey != key { dashboard = nil; catalog = nil; labPayload = nil }
        session.begin(accountKey: key)
        persist(immediate: true)
    }

    func signOut() {
        reloadTask?.cancel()
        session.signOut(); dashboard = nil; catalog = nil; labPayload = nil
        persist(immediate: true)
    }

    func receive(_ payload: CustomerV2DashboardPayload, ticket: UUID) {
        guard ticket == session.generation, let id = payload.member?.id else { return }
        let key = SHA256.hash(data: Data("myfitbites-widget-account:\(id)".utf8)).map { String(format: "%02x", $0) }.joined()
        guard key == session.snapshot.accountKey else { return }
        dashboard = payload
        let accepted = session.accept(ticket) { snapshot in
            let completed = (payload.orders?.pastItems ?? []).filter { $0.status == "completed" && ($0.sortTime ?? 0) > 0 }
            let dates = completed.compactMap { $0.sortTime }.map { Date(timeIntervalSince1970: Double($0)) }.sorted(by: >)
            func stat(_ name: String) -> Int? {
                payload.stats?.first { $0.label == name }?.value?.value.split(separator: " ").first.flatMap { Int($0) }
            }
            if let count = stat("Current streak") {
                var streak = WidgetSnapshot.Streak(count: max(0, count), longest: max(0, stat("Longest streak") ?? count), lastOrderDate: dates.first, knownOrderDays: [])
                streak.knownOrderDays = Array(Set(dates.map(streak.dayKey))).sorted()
                // Mark only observed days. The endpoint's pagination can omit qualifying sales.
                streak.historyCompleteFrom = nil
                let uniqueDates = Array(Set(dates.map { streak.calendar().startOfDay(for: $0) })).sorted(by: >)
                if uniqueDates.count > 1 {
                    streak.returning = (streak.calendar().dateComponents([.day], from: uniqueDates[1], to: uniqueDates[0]).day ?? 0) > 1
                }
                snapshot.streak = .init(value: streak)
            }
            if let member = payload.member, let level = member.level, level > 0,
               let tier = member.tier, !tier.isEmpty, let xp = member.levelXp, xp >= 0,
               let target = member.levelTarget, target >= 0 {
                snapshot.member = .init(value: .init(level: level, tier: tier, levelXP: xp, levelTarget: target))
            } else { snapshot.member = nil }
            if let loyalty = payload.loyalty, let stamps = loyalty.stamps, let target = loyalty.target, target > 0 {
                snapshot.loyalty = .init(value: .init(stamps: max(0, min(target, stamps)), target: target, rewards: max(0, loyalty.rewards ?? 0)))
            }
        }
        if accepted { updateOrders(); updateLab(); persist() }
    }

    func receive(_ payload: CustomerV2RewardsSummaryPayload, ticket: UUID) {
        guard session.accept(ticket, update: { snapshot in
            if let loyalty = payload.loyalty, let stamps = loyalty.stamps, let target = loyalty.target, target > 0 {
                snapshot.loyalty = .init(value: .init(stamps: max(0, min(target, stamps)), target: target, rewards: max(0, loyalty.rewards ?? 0)))
            }
        }) else { return }
        persist()
    }

    func receive(_ payload: CustomerV2StorePayload, ticket: UUID) {
        guard ticket == session.generation, session.snapshot.accountKey != nil else { return }
        guard let fresh = CustomerV2Mapper.catalog(from: payload, fallback: LocalCatalogRepository().catalog()) else {
            _ = session.accept(ticket) { $0.recipe = nil }
            persist()
            return
        }
        catalog = fresh
        _ = session.accept(ticket) { snapshot in
            if let promotion = fresh.homePromotion, let id = promotion.productID,
               let product = fresh.products.first(where: { $0.id == id && $0.isAvailable }) {
                snapshot.recipe = .init(value: .init(productID: String(product.inventoryItemID), name: product.name,
                    eyebrow: promotion.eyebrow.isEmpty ? "ON THE MENU" : promotion.eyebrow))
            } else { snapshot.recipe = nil }
        }
        updateOrders(); persist()
    }

    func receive(_ payload: CustomerV2TooLabPayload, ticket: UUID) {
        guard ticket == session.generation, session.snapshot.accountKey != nil else { return }
        labPayload = payload
        updateLab(); persist()
    }

    func receive(_ payload: ArcadeSummary, ticket: UUID) {
        guard session.accept(ticket, update: { snapshot in
            snapshot.arcade = .init(value: .init(credits: max(0, payload.credits.total), enabled: payload.paidEntryEnabled,
                resetsAt: ISO8601DateFormatter().date(from: payload.credits.resetsAt)))
        }) else { return }
        persist()
    }

    private func updateOrders() {
        guard let dashboard, let catalog, dashboard.orders?.pastItems != nil else { return }
        let fresh = CustomerV2Mapper.dashboard(from: dashboard, fallback: LocalDashboardRepository().dashboard())
        let products = Dictionary(catalog.products.map { ($0.inventoryItemID, $0) }, uniquingKeysWith: { a, _ in a })
        let orders = fresh.pastOrders.filter { order in
            order.status == "completed" && !order.reorderItems.isEmpty && order.reorderItems.allSatisfy { item in
                guard let product = products[item.productID], product.isAvailable else { return false }
                return Set(item.toppingIDs).isSubset(of: Set(product.toppings.map(\.toppingID)))
            }
        }.prefix(3).map { order in
            let product = order.reorderItems.first.flatMap { products[$0.productID] }
            return WidgetSnapshot.Reorder(id: order.id, name: order.reorderItems.count == 1 ? (product?.name ?? order.items) : order.items,
                                          itemCount: order.reorderItems.reduce(0) { $0 + $1.quantity },
                                          imageName: order.reorderItems.count == 1 ? product?.imageName : nil)
        }
        _ = session.accept(ticket) { $0.orders = .init(value: orders) }
    }

    private func updateLab() {
        guard let dashboard, let labPayload, labPayload.totalLxp != nil else { return }
        let fresh = CustomerV2Mapper.dashboard(from: dashboard, fallback: LocalDashboardRepository().dashboard())
        let progress = CustomerV2Mapper.tooLabProgress(from: labPayload)
        let access = TooLabAccessState(dashboard: fresh, labXP: progress.totalLXP)
        let discoveries = access.prototypePreviews.filter(access.canBuy).map {
            WidgetSnapshot.Discovery(id: $0.id, name: $0.name, imageName: $0.imageName, clearance: $0.requiredClearance.code)
        }
        _ = session.accept(ticket) { $0.lab = .init(value: .init(unlocked: access.isLabUnlocked, lxp: progress.totalLXP, clearance: access.clearance.code, discoveries: discoveries)) }
    }

    private func persist(immediate: Bool = false) {
        do { try store.write(session.snapshot) }
        catch {
            // Fail closed when logging out: remove any old account's file if an atomic replacement failed.
            if session.snapshot.status == .signedOut, let directory = store.directory {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("widget-snapshot-v1.json"))
            }
        }
        reloadTask?.cancel()
        if immediate { WidgetCenter.shared.reloadAllTimelines(); return }
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
