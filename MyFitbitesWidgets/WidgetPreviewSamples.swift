#if DEBUG
import SwiftUI
import WidgetKit

// Illustrative values are used only by Xcode previews and the separate verification app.
enum WidgetPreviewSamples {
    static func snapshot(at date: Date = Date()) -> WidgetSnapshot {
        var s = WidgetSnapshot()
        s.accountKey = "preview-only"; s.sessionID = "preview-session"; s.status = .ready; s.updatedAt = date
        var streak = WidgetSnapshot.Streak(count: 4, longest: 12, lastOrderDate: date, knownOrderDays: [])
        streak.knownOrderDays = (-3...0).map { streak.dayKey(date.addingTimeInterval(Double($0) * 86400)) }
        s.streak = .init(value: streak, fetchedAt: date)
        s.loyalty = .init(value: .init(stamps: 6, target: 9, rewards: 1), fetchedAt: date)
        s.orders = .init(value: [
            .init(id: 101, name: "Greek Yogurt Blueberry", itemCount: 1, imageName: nil),
            .init(id: 102, name: "Protein Crepe", itemCount: 2, imageName: nil),
            .init(id: 103, name: "Tirami Oats", itemCount: 1, imageName: nil)
        ], fetchedAt: date)
        s.lab = .init(value: .init(unlocked: true, lxp: 5200, clearance: "C4", discoveries: [
            .init(id: "choco-mulberry-crunch", name: "CHOCO MULBERRY CRUNCH", imageName: "ProductGreekYogurtBlueberry", clearance: "C3"),
            .init(id: "crepe-reactor-berry", name: "CREPE REACTOR BERRY", imageName: "ProductProteinCrepe", clearance: "C4")
        ]), fetchedAt: date)
        return s
    }
    static var entry: FitbitesEntry {
        FitbitesEntry(date: Date(), configuration: CompanionConfiguration(), snapshot: snapshot())
    }
}

#Preview("Tiel • order streak", as: .systemMedium) { OrderStreakWidget() } timeline: { WidgetPreviewSamples.entry }
#Preview("B cookies • card", as: .systemSmall) { LoyaltyStampsWidget() } timeline: { WidgetPreviewSamples.entry }
#Preview("B cookie card", as: .systemMedium) { LoyaltyStampsWidget() } timeline: { WidgetPreviewSamples.entry }
#endif
