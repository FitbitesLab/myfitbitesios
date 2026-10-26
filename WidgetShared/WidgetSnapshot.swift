import Foundation

// Shared, credential-free contract. Only the app writes this snapshot.
struct WidgetSnapshot: Codable, Equatable {
    static let version = 1
    var version = Self.version
    var accountKey: String?
    var sessionID = UUID().uuidString
    var status: Status = .signedOut
    var updatedAt = Date()
    var streak: Timed<Streak>?
    var loyalty: Timed<Loyalty>?
    var orders: Timed<[Reorder]>?
    var lab: Timed<Lab>?
    var member: Timed<MemberProgress>?
    var recipe: Timed<RecipeFeature>?
    var arcade: Timed<ArcadeFeature>?
    enum Status: String, Codable { case signedOut, loading, ready, unavailable }
    struct Timed<Value: Codable & Equatable>: Codable, Equatable {
        var value: Value
        var fetchedAt = Date()
        func isStale(at date: Date) -> Bool { date.timeIntervalSince(fetchedAt) >= 6 * 3600 }
        func isExpiredForToday(at date: Date) -> Bool { date.timeIntervalSince(fetchedAt) >= 24 * 3600 }
    }
    struct Streak: Codable, Equatable {
        var count: Int
        var longest: Int
        // CustomerXpService currently uses config('app.timezone'), UTC, NOT the Lab timezone.
        var timezone = "UTC"
        var lastOrderDate: Date?
        var knownOrderDays: [String]
        // The dashboard returns a bounded history. Unreported dates are unknown, never "missed".
        var historyCompleteFrom: String?
        var returning = false
        func calendar() -> Calendar {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)!
            return c
        }
        func dayKey(_ date: Date) -> String {
            let c = calendar().dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        }
        func daysSinceOrder(at date: Date) -> Int? {
            guard let lastOrderDate else { return nil }
            return calendar().dateComponents([.day], from: calendar().startOfDay(for: lastOrderDate), to: calendar().startOfDay(for: date)).day
        }
        func currentCount(at date: Date, fetchedAt: Date) -> Int? {
            // Never guess a new count from truncated history or carry yesterday's value indefinitely.
            if calendar().isDate(date, inSameDayAs: fetchedAt) { return max(0, count) }
            guard let days = daysSinceOrder(at: date) else { return nil }
            return days > 1 ? 0 : max(0, count)
        }
        func missedOrderDays(at date: Date) -> Int? {
            guard let days = daysSinceOrder(at: date), days >= 0 else { return nil }
            // Today is still in progress. Count only fully elapsed business-calendar days.
            return max(0, days - 1)
        }
        func tielPose(at date: Date) -> String {
            guard let days = daysSinceOrder(at: date), let missed = missedOrderDays(at: date) else { return "tiel_welcome_back" }
            if returning && days == 0 { return "tiel_welcome_back" }
            if missed == 0 && count > 0 { return "tiel_streak_approving" }
            switch missed {
            case 1: return "tiel_streak_wings_crossed"
            case 2: return "tiel_streak_tiny_dinosaur"
            case 3...: return "tiel_guarding_cookies"
            default: return "tiel_welcome_back"
            }
        }
        var nextBonus: (days: Int, percent: Int)? {
            // CustomerXpService.calculateStreakBonus: order XP bonus, never b cookies or LXP.
            [(2, 5), (3, 10), (4, 15), (5, 20), (6, 50)].first { $0.0 > count }
        }
    }
    struct Loyalty: Codable, Equatable {
        var stamps: Int
        var target: Int
        var rewards: Int
        // The ninth stamp is exchanged server-side: stamps resets to zero and rewards increases.
        // An available reward takes priority until claimed; never fabricate the new card's count.
        var rewardReady: Bool { rewards > 0 }
        var tooPose: String {
            if rewardReady { return "too_reward_celebration" }
            return stamps > 0 ? "too_cookie_jar" : "too_welcome"
        }
        var displayedCardStamps: Int { rewardReady ? max(1, target) : max(0, min(target, stamps)) }
        var commentIndex: Int { rewardReady ? 9 : max(0, min(8, stamps)) }
    }
    struct MemberProgress: Codable, Equatable {
        var level: Int
        var tier: String
        var levelXP: Int
        var levelTarget: Int
        // The backend sends target zero at its maximum level. Never divide by zero.
        var isMaximumLevel: Bool { levelTarget == 0 }
        var progress: Double { isMaximumLevel ? 1 : min(1, max(0, Double(levelXP) / Double(max(1, levelTarget)))) }
    }
    struct RecipeFeature: Codable, Equatable {
        var productID: String
        var name: String
        // This is the publisher's live label, not a guessed release date.
        var eyebrow: String
    }
    struct ArcadeFeature: Codable, Equatable {
        var credits: Int
        var enabled: Bool
        var resetsAt: Date?
    }

    func availableTodayKinds(at date: Date) -> [WidgetTodayKind] {
        guard status == .ready else { return [] }
        var kinds: [WidgetTodayKind] = []
        if let lab, !lab.isExpiredForToday(at: date), lab.value.unlocked, !lab.value.discoveries.isEmpty { kinds.append(.lab) }
        if let recipe, !recipe.isExpiredForToday(at: date), !recipe.value.name.isEmpty { kinds.append(.recipe) }
        if let member, !member.isExpiredForToday(at: date) { kinds.append(.member) }
        if let arcade, !arcade.isExpiredForToday(at: date), arcade.value.enabled,
           arcade.value.resetsAt.map({ date < $0 }) ?? false { kinds.append(.arcade) }
        return kinds
    }

    func todayFetchedAt(_ kind: WidgetTodayKind) -> Date? {
        switch kind {
        case .lab: lab?.fetchedAt
        case .member: member?.fetchedAt
        case .recipe: recipe?.fetchedAt
        case .arcade: arcade?.fetchedAt
        }
    }

    func todayKind(preferred: WidgetTodayKind? = nil, at date: Date) -> WidgetTodayKind? {
        let available = availableTodayKinds(at: date)
        if let preferred { return available.contains(preferred) ? preferred : nil }
        guard !available.isEmpty else { return nil }
        // Rotate by the Fitbites business day, never the device time zone or hour.
        let slot = WidgetTodayCalendar.dayNumber(date)
        return available[((slot % available.count) + available.count) % available.count]
    }

    struct Reorder: Codable, Equatable, Identifiable {
        var id: Int
        var name: String
        var itemCount: Int
        var imageName: String?
    }
    struct Lab: Codable, Equatable {
        var unlocked: Bool
        var lxp: Int
        var clearance: String
        var discoveries: [Discovery]
    }
    struct Discovery: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var imageName: String
        var clearance: String
    }
}

enum WidgetTopic: String, CaseIterable, Codable { case streak, cookies, stamps, reorder, lab, today }

enum WidgetTodayKind: String, CaseIterable, Codable { case lab, member, recipe, arcade }

struct WidgetRoute: Equatable {
    let topic: WidgetTopic
    let itemID: String?
    let sessionID: String?
    init(topic: WidgetTopic, itemID: String? = nil, sessionID: String? = nil) {
        self.topic = topic; self.itemID = itemID; self.sessionID = sessionID
    }
    init?(url: URL) {
        guard url.scheme == "myfitbites", url.host == "widget", url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let topic = WidgetTopic(rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
              components.queryItems?.allSatisfy({ ["item", "session"].contains($0.name) }) ?? true else { return nil }
        let query = components.queryItems ?? []
        guard Set(query.map(\.name)).count == query.count else { return nil }
        let item = query.first { $0.name == "item" }?.value
        guard item == nil || (item!.count <= 100 && item!.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        self.init(topic: topic, itemID: item, sessionID: query.first { $0.name == "session" }?.value)
    }
    var url: URL {
        var c = URLComponents()
        c.scheme = "myfitbites"; c.host = "widget"; c.path = "/\(topic.rawValue)"
        c.queryItems = [itemID.map { URLQueryItem(name: "item", value: $0) }, sessionID.map { URLQueryItem(name: "session", value: $0) }].compactMap { $0 }
        return c.url!
    }
}


enum WidgetTodayCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }
    static func dayNumber(_ date: Date) -> Int {
        // Derive the slot from local midnight. Foundation's day-in-era ordinality can
        // retain the previous ordinal at midnight even when date components advance.
        Int(floor(calendar.startOfDay(for: date).timeIntervalSince1970 / 86400))
    }
    static func nextDay(after date: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))! }
}
