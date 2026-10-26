import SwiftUI
import WidgetKit

@main
struct MyFitbitesWidgetCollection: WidgetBundle {
    var body: some Widget {
        OrderStreakWidget()
        LoyaltyStampsWidget()
        TodayAtFitbitesWidget()
        MyFitbitesOverviewWidget()
        MemberProgressWidget()
        ReorderWidget()
    }
}

struct FitbitesEntry: TimelineEntry {
    let date: Date
    let configuration: CompanionConfiguration
    let snapshot: WidgetSnapshot
    var todayPreference: WidgetTodayKind? = nil
}

struct FitbitesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FitbitesEntry {
        // Gallery placeholders never display fabricated balances.
        FitbitesEntry(date: Date(), configuration: CompanionConfiguration(), snapshot: WidgetSnapshot())
    }
    func snapshot(for configuration: CompanionConfiguration, in context: Context) async -> FitbitesEntry {
        FitbitesEntry(date: Date(), configuration: configuration, snapshot: WidgetSnapshotStore().read())
    }
    func timeline(for configuration: CompanionConfiguration, in context: Context) async -> Timeline<FitbitesEntry> {
        let snapshot = WidgetSnapshotStore().read()
        let now = Date()
        var dates = [now, now.addingTimeInterval(6 * 3600)]
        let calendar = snapshot.streak?.value.calendar() ?? Calendar(identifier: .gregorian)
        let midnight = calendar.startOfDay(for: now).addingTimeInterval(86400)
        dates.append(midnight)
        // Small cards must change state when the cached data crosses a freshness boundary.
        for fetched in [snapshot.member?.fetchedAt, snapshot.loyalty?.fetchedAt, snapshot.orders?.fetchedAt].compactMap({ $0 }) {
            dates += [6.0, 24.0].map { fetched.addingTimeInterval($0 * 3600) }.filter { $0 > now }
        }
        // Timelines update date-dependent states locally. The containing app refreshes account data.
        let entries = Set(dates).sorted().map { FitbitesEntry(date: $0, configuration: configuration, snapshot: snapshot) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600)))
    }
}

struct OrderStreakWidget: Widget {
    let kind = "MyFitbites.OrderStreak"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CompanionConfiguration.self, provider: FitbitesProvider()) { FitbitesWidgetView(entry: $0, topic: .streak) }
            .configurationDisplayName("Order streak")
            .description("Your completed-order streak, with Too and Tiel.")
            .supportedFamilies([.systemMedium]).contentMarginsDisabled()
    }
}
struct BCookieBalanceWidget: Widget {
    let kind = "MyFitbites.BCookieBalance"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CompanionConfiguration.self, provider: FitbitesProvider()) { FitbitesWidgetView(entry: $0, topic: .cookies) }
            .configurationDisplayName("B cookies")
            .description("Your B cookies are your loyalty stamps. Collect nine for a free Fitbites reward.")
            .supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}
struct LoyaltyStampsWidget: Widget {
    let kind = "MyFitbites.LoyaltyStamps"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CompanionConfiguration.self, provider: FitbitesProvider()) { FitbitesWidgetView(entry: $0, topic: .stamps) }
            .configurationDisplayName("Loyalty card")
            .description("Your stamp card and next free Fitbites reward.")
            .supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}
struct ReorderWidget: Widget {
    let kind = "MyFitbites.Reorder"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CompanionConfiguration.self, provider: FitbitesProvider()) { FitbitesWidgetView(entry: $0, topic: .reorder) }
            .configurationDisplayName("Order again")
            .description("Review a recent order with current prices before checkout.")
            .supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}
struct TooLabWidget: Widget {
    let kind = "MyFitbites.TooLab"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CompanionConfiguration.self, provider: FitbitesProvider()) { FitbitesWidgetView(entry: $0, topic: .lab) }
            .configurationDisplayName("Too’s Lab")
            .description("Explore experiments your current clearance can access.")
            .supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}


struct TodayAtFitbitesProvider: AppIntentTimelineProvider {
    func entry(_ snapshot: WidgetSnapshot, date: Date, configuration: TodayConfiguration) -> FitbitesEntry {
        let common = CompanionConfiguration()
        common.appearance = configuration.appearance
        common.comments = configuration.comments
        return FitbitesEntry(date: date, configuration: common, snapshot: snapshot, todayPreference: configuration.content.kind)
    }
    func placeholder(in context: Context) -> FitbitesEntry {
        entry(WidgetSnapshot(), date: Date(), configuration: TodayConfiguration())
    }
    func snapshot(for configuration: TodayConfiguration, in context: Context) async -> FitbitesEntry {
        let snapshot = WidgetSnapshotStore().read()
        let now = Date()
        var result = entry(snapshot, date: now, configuration: configuration)
        result.todayPreference = configuration.content.kind ?? WidgetTodaySelectionStore().selection(for: snapshot, at: now)
        return result
    }
    func timeline(for configuration: TodayConfiguration, in context: Context) async -> Timeline<FitbitesEntry> {
        let snapshot = WidgetSnapshotStore().read()
        let now = Date()
        let tomorrow = WidgetTodayCalendar.nextDay(after: now)
        let selected = configuration.content.kind ?? WidgetTodaySelectionStore().selection(for: snapshot, at: now)
        var dates = [now, tomorrow]
        dates += [snapshot.member?.fetchedAt, snapshot.recipe?.fetchedAt, snapshot.lab?.fetchedAt, snapshot.arcade?.fetchedAt]
            .flatMap { stamp in [6.0, 24.0].compactMap { hours in stamp?.addingTimeInterval(hours * 3600) } }.filter { $0 > now && $0 < tomorrow }
        if let reset = snapshot.arcade?.value.resetsAt, reset > now, reset < tomorrow { dates.append(reset) }
        let entries = Set(dates).sorted().map { date in
            var result = entry(snapshot, date: date, configuration: configuration)
            // Future midnight entries are predictions; only persist the choice for the current day.
            result.todayPreference = date < tomorrow ? selected : (configuration.content.kind ?? snapshot.todayKind(at: date))
            return result
        }
        return Timeline(entries: entries, policy: .after(min(tomorrow, now.addingTimeInterval(6 * 3600))))
    }
}

struct TodayAtFitbitesWidget: Widget {
    let kind = "MyFitbites.Today"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TodayConfiguration.self, provider: TodayAtFitbitesProvider()) {
            TodayAtFitbitesView(entry: $0)
        }
        .configurationDisplayName("Today at Fitbites")
        .description("Too’s creations, your member progress, recipe news and My Arcade.")
        .supportedFamilies([.systemMedium]).contentMarginsDisabled()
    }
}


struct MyFitbitesOverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> FitbitesEntry {
        FitbitesEntry(date: Date(), configuration: CompanionConfiguration(), snapshot: WidgetSnapshot())
    }
    func getSnapshot(in context: Context, completion: @escaping (FitbitesEntry) -> Void) {
        completion(FitbitesEntry(date: Date(), configuration: CompanionConfiguration(), snapshot: WidgetSnapshotStore().read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FitbitesEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore().read()
        let now = Date()
        let refresh = now.addingTimeInterval(6 * 3600)
        var dates = [now, refresh]
        for fetched in [snapshot.member?.fetchedAt, snapshot.loyalty?.fetchedAt, snapshot.orders?.fetchedAt].compactMap({ $0 }) {
            dates += [6.0, 24.0].map { fetched.addingTimeInterval($0 * 3600) }.filter { $0 > now }
        }
        let entries = Set(dates).sorted().map { FitbitesEntry(date: $0, configuration: CompanionConfiguration(), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct MyFitbitesOverviewWidget: Widget {
    let kind = "MyFitbites.Overview"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MyFitbitesOverviewProvider()) { MyFitbitesOverviewView(entry: $0) }
            .configurationDisplayName("MYFITBITES")
            .description("Your level and XP, B-cookie loyalty card, and a favourite to order again.")
            .supportedFamilies([.systemLarge]).contentMarginsDisabled()
    }
}


struct MemberProgressWidget: Widget {
    let kind = "MyFitbites.MemberProgress"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MyFitbitesOverviewProvider()) { MyFitbitesSmallView(entry: $0, model: .member) }
            .configurationDisplayName("Level & XP")
            .description("Your member level, tier and progress to the next level.")
            .supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}
