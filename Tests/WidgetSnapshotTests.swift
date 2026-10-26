import Foundation

@main struct WidgetSnapshotTests {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label); count += 1
        }
        let parse: (String) -> Date = { ISO8601DateFormatter().date(from: $0)! }
        let today = parse("2026-10-26T10:00:00Z")
        var s = WidgetSnapshot.Streak(count: 4, longest: 9, lastOrderDate: today, knownOrderDays: ["2026-10-26"])
        check(s.currentCount(at: today, fetchedAt: today) == 4, "current count")
        check(s.currentCount(at: parse("2026-10-27T23:00:00Z"), fetchedAt: today) == 4, "yesterday remains active")
        check(s.currentCount(at: parse("2026-10-28T00:00:00Z"), fetchedAt: today) == 0, "break at server midnight")
        check(s.tielPose(at: today) == "tiel_streak_approving", "active pose")
        check(s.tielPose(at: parse("2026-10-27T23:59:59Z")) == "tiel_streak_approving", "today is not a missed day before the business midnight")
        check(s.missedOrderDays(at: parse("2026-10-28T00:00:00Z")) == 1, "first missed day at server midnight")
        check(s.tielPose(at: parse("2026-10-28T00:00:00Z")) == "tiel_streak_wings_crossed", "one missed day pose")
        check(s.tielPose(at: parse("2026-10-29T00:00:00Z")) == "tiel_streak_tiny_dinosaur", "two missed days pose")
        check(s.tielPose(at: parse("2026-10-30T00:00:00Z")) == "tiel_guarding_cookies", "three missed days pose")
        check(s.tielPose(at: parse("2026-11-03T12:00:00Z")) == "tiel_guarding_cookies", "cookie pose remains after three missed days")
        check(s.currentCount(at: parse("2026-10-29T12:00:00Z"), fetchedAt: today) == 0, "three inactive days are not an active streak")
        check(s.dayKey(parse("2026-10-26T23:59:59Z")) == "2026-10-26", "server UTC, not device timezone")
        check(s.nextBonus?.days == 5 && s.nextBonus?.percent == 20, "real order XP milestone")
        s.count = 6; check(s.nextBonus == nil, "no invented milestone above maximum")
        s.returning = true; check(s.tielPose(at: today) == "tiel_welcome_back", "warm return")
        s.lastOrderDate = nil
        check(s.missedOrderDays(at: today) == nil && s.tielPose(at: today) == "tiel_welcome_back", "unknown history never becomes a missed-day pose")
        check(s.currentCount(at: parse("2026-10-27T12:00:00Z"), fetchedAt: today) == nil, "missing history expires safely")
        check(s.historyCompleteFrom == nil, "bounded history does not imply missed days")
        var loyalty = WidgetSnapshot.Loyalty(stamps: 8, target: 9, rewards: 0)
        check(loyalty.tooPose == "too_cookie_jar" && loyalty.commentIndex == 8, "eighth stamp is still collecting")
        loyalty.stamps = 0; loyalty.rewards = 1
        check(loyalty.rewardReady && loyalty.tooPose == "too_reward_celebration" && loyalty.commentIndex == 9, "server rollover displays earned reward, not an empty card")
        check(loyalty.stamps == 0 && loyalty.displayedCardStamps == 9, "completed-card display does not mutate the current card")
        loyalty.stamps = 2
        check(loyalty.rewardReady && loyalty.tooPose == "too_reward_celebration", "available reward remains claimable alongside a new partial card")
        loyalty.rewards = 0
        check(loyalty.tooPose == "too_cookie_jar" && loyalty.commentIndex == 2 && loyalty.displayedCardStamps == 2, "claimed reward reveals actual partial card")
        loyalty.stamps = 0
        check(!loyalty.rewardReady && loyalty.tooPose == "too_welcome" && loyalty.commentIndex == 0, "empty new card waves after reward claimed")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        check(store.read().status == .signedOut, "first install signed out")
        var session = WidgetSnapshotSession()
        session.begin(accountKey: "A")
        let ticketA = session.generation
        check(session.accept(ticketA) { $0.loyalty = .init(value: .init(stamps: 8, target: 9, rewards: 2), fetchedAt: today) }, "accepted account snapshot")
        try store.write(session.snapshot)
        check(store.read().loyalty?.value.stamps == 8, "real store round trip")
        let previousID = session.snapshot.sessionID
        session.begin(accountKey: "B")
        check(session.snapshot.loyalty == nil && session.snapshot.sessionID != previousID, "switch clears prior data and links")
        check(!session.accept(ticketA) { $0.loyalty = .init(value: .init(stamps: 8, target: 9, rewards: 2)) }, "late previous-user response rejected")
        let ticketB = session.generation
        session.signOut(); try store.write(session.snapshot)
        check(!session.accept(ticketB) { $0.status = .ready }, "late logout response rejected")
        check(store.read().status == .signedOut && store.read().accountKey == nil, "logout persisted without identity")
        session.begin(accountKey: "A")
        let sameID = session.snapshot.sessionID
        session.begin(accountKey: "A")
        check(session.snapshot.sessionID == sameID, "same login retains widget routes")
        let route = WidgetRoute(topic: .reorder, itemID: "51", sessionID: sameID)
        check(WidgetRoute(url: route.url) == route, "reorder round trip")
        for invalid in ["https://widget/reorder", "myfitbites://wrong/lab", "myfitbites://widget/pay", "myfitbites://widget/reorder?item=1&item=2", "myfitbites://widget/reorder?item=../private", "myfitbites://widget/lab?token=secret"] {
            check(WidgetRoute(url: URL(string: invalid)!) == nil, "reject unsafe route")
        }
        let old = WidgetSnapshot.Timed(value: WidgetSnapshot.Loyalty(stamps: 0, target: 9, rewards: 0), fetchedAt: today)
        check(!old.isStale(at: today) && old.isStale(at: today.addingTimeInterval(21600)), "staleness clock")
        try Data("bad JSON".utf8).write(to: dir.appendingPathComponent("widget-snapshot-v1.json"))
        check(store.read().status == .unavailable && store.read().loyalty == nil, "corrupt storage fails closed")
        // The Today card follows the Vietnam day and is pinned across refreshes.
        let morning = parse("2026-10-26T00:00:00Z")
        let beforeMidnight = parse("2026-10-26T16:59:59Z")
        let midnight = parse("2026-10-26T17:00:00Z")
        var daily = WidgetSnapshot(); daily.status = .ready; daily.accountKey = "daily-test"
        daily.member = .init(value: .init(level: 12, tier: "Too's Apprentice", levelXP: 1120, levelTarget: 1600), fetchedAt: morning)
        daily.recipe = .init(value: .init(productID: "103", name: "Tirami Oats", eyebrow: "NEW RECIPE"), fetchedAt: morning)
        daily.lab = .init(value: .init(unlocked: true, lxp: 5200, clearance: "C4", discoveries: [.init(id: "example", name: "Example", imageName: "", clearance: "C3")]), fetchedAt: morning)
        daily.arcade = .init(value: .init(credits: 2, enabled: true, resetsAt: midnight.addingTimeInterval(86400)), fetchedAt: morning)
        check(WidgetTodayCalendar.nextDay(after: morning) == midnight, "Today rolls over at Vietnam midnight")
        check(daily.todayKind(at: morning) == daily.todayKind(at: beforeMidnight), "no hourly reshuffle within one Vietnam day")
        check(daily.todayKind(at: beforeMidnight) != daily.todayKind(at: midnight), "next day rotates the featured card")
        check(daily.member!.value.progress == 0.7, "member bar uses level XP, not lifetime or Lab XP")
        var maximum = WidgetSnapshot.MemberProgress(level: 99, tier: "Golden Feather", levelXP: 999, levelTarget: 0)
        check(maximum.isMaximumLevel && maximum.progress == 1, "maximum level has a full bar and no division by zero")
        maximum.levelTarget = 100; maximum.levelXP = 200
        check(maximum.progress == 1, "XP bar clamps above target")
        maximum.levelXP = -1; check(maximum.progress == 0, "XP bar clamps below zero")
        let dailyChoices = WidgetTodaySelectionStore(directory: dir.appendingPathComponent("daily"))
        let selected = dailyChoices.selection(for: daily, at: morning)!
        var changed = daily
        changed.recipe = nil
        changed.member = nil
        check(dailyChoices.selection(for: changed, at: morning.addingTimeInterval(3600)) == selected, "refreshing feed does not reshuffle today's choice")
        var otherAccount = daily; otherAccount.sessionID = "different-session"; otherAccount.lab = nil; otherAccount.recipe = nil; otherAccount.arcade = nil
        check(dailyChoices.selection(for: otherAccount, at: morning) == .member, "daily choice is isolated across account sessions")
        let nextChoice = dailyChoices.selection(for: daily, at: midnight)
        check(nextChoice == daily.todayKind(at: midnight), "persisted daily selection expires at business midnight")
        daily.arcade?.value.resetsAt = midnight
        check(!daily.availableTodayKinds(at: midnight).contains(.arcade), "never carry old Arcade credit count over its reset")
        daily.lab?.value.unlocked = false
        check(!daily.availableTodayKinds(at: morning).contains(.lab), "locked Lab discoveries remain private")
        daily.arcade?.value.enabled = false
        check(!daily.availableTodayKinds(at: morning).contains(.arcade), "disabled Arcade is not promoted")
        check(daily.todayKind(preferred: .lab, at: morning) == nil, "fixed category never silently substitutes another card")
        check(daily.availableTodayKinds(at: morning.addingTimeInterval(86400)).isEmpty, "expired content never becomes a fresh daily feature")
        daily.status = .signedOut
        check(daily.availableTodayKinds(at: morning).isEmpty && dailyChoices.selection(for: daily, at: morning) == nil, "signed-out account cannot show private Today data")
        let todayRoute = WidgetRoute(topic: .today, itemID: "recipe-103", sessionID: sameID)
        check(WidgetRoute(url: todayRoute.url) == todayRoute, "Today recipe route round trip")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(otherAccount)) as! [String: Any]
        for key in ["member", "recipe", "arcade"] { legacy.removeValue(forKey: key) }
        let decodedLegacy = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(decodedLegacy.member == nil && decodedLegacy.recipe == nil && decodedLegacy.arcade == nil, "existing snapshots migrate without fabricated Today values")
        print("PASS: \(count) widget snapshot, privacy, time and routing checks")
    }
}
