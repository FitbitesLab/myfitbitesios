import SwiftUI
import WidgetKit

struct FitbitesWidgetView: View {
    let entry: FitbitesEntry
    let topic: WidgetTopic
    @Environment(\.widgetFamily) private var widgetFamily
    #if DEBUG
    var previewFamily: WidgetFamily? = nil
    #endif
    private var family: WidgetFamily {
        #if DEBUG
        return previewFamily ?? widgetFamily
        #else
        return widgetFamily
        #endif
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var typeSize
    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var dark: Bool { entry.configuration.appearance == .espresso || (entry.configuration.appearance == .system && colorScheme == .dark) }
    private var ink: Color { renderingMode == .fullColor ? (dark ? Color(red: 1, green: 0.94, blue: 0.81) : Color(red: 0.24, green: 0.15, blue: 0.10)) : .primary }
    private var gold: Color { dark ? Color(red: 0.96, green: 0.73, blue: 0.35) : Color(red: 0.68, green: 0.36, blue: 0.10) }
    // Tiel artwork is reserved for Order Streak states. Other topics use their supplied Too poses.
    private var companion: WidgetCompanion { topic == .streak ? entry.configuration.companion : .too }
    private var title: String { topic.title }
    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }
    private var stamp: Date? {
        switch topic {
        case .streak: snapshot.streak?.fetchedAt
        case .cookies: snapshot.loyalty?.fetchedAt
        case .stamps: snapshot.loyalty?.fetchedAt
        case .reorder: snapshot.orders?.fetchedAt
        case .lab: snapshot.lab?.fetchedAt
        case .today: snapshot.member?.fetchedAt
        }
    }
    private var isStale: Bool { stamp.map { entry.date.timeIntervalSince($0) >= 6 * 3600 } ?? false }
    private var unavailableText: String? {
        switch snapshot.status {
        case .signedOut: return widgetCopy("Sign in to MyFitbites", "Đăng nhập MyFitbites")
        case .loading: return widgetCopy("Open app to sync", "Mở ứng dụng để cập nhật")
        case .unavailable: return widgetCopy("Open app to reconnect", "Mở ứng dụng để kết nối")
        case .ready: return stamp == nil ? widgetCopy("Open app to update", "Mở ứng dụng để cập nhật") : nil
        }
    }
    private var route: WidgetRoute {
        let id: String?
        if isStale { id = nil }
        else if topic == .reorder { id = snapshot.orders?.value.first.map { String($0.id) } }
        else if topic == .lab { id = snapshot.lab?.value.discoveries.first?.id }
        else { id = nil }
        return WidgetRoute(topic: topic, itemID: id, sessionID: snapshot.sessionID)
    }

    var body: some View {
        if topic == .today { TodayAtFitbitesView(entry: entry) }
        else if family == .systemSmall && topic == .stamps { MyFitbitesSmallView(entry: entry, model: .loyalty) }
        else if family == .systemSmall && topic == .reorder { MyFitbitesSmallView(entry: entry, model: .reorder) }
        else { standardBody }
    }

    private var standardBody: some View {
        GeometryReader { proxy in
            Group {
                if family == .systemMedium {
                    if let text = unavailableText { mediumUnavailable(text, size: proxy.size) }
                    else if topic == .streak { mediumStreak(size: proxy.size) }
                    else if topic == .stamps { mediumLoyalty(size: proxy.size) }
                    else { medium(size: proxy.size) }
                } else if let text = unavailableText { empty(text, size: proxy.size) }
                else if isSmall { small(size: proxy.size) }
                else { large(size: proxy.size) }
            }
            .padding(isSmall ? 12 : (isLarge ? 16 : 0))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .foregroundStyle(ink)
        .fontDesign(.rounded)
        .containerBackground(for: .widget) { backdrop }
        .widgetURL(route.url)
        .privacySensitive()
    }

    @ViewBuilder private var backdrop: some View {
        if renderingMode == .fullColor && family == .systemMedium && !dark {
            Color.white
        } else if renderingMode == .fullColor {
            GeometryReader { proxy in
                Image(dark ? "widget_espresso_dark" : (topic == .lab ? "widget_lab" : "widget_cafe_cream"))
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading).clipped()
                    .accessibilityHidden(true)
            }
        } else { Color.clear }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image("FitbitesLogo").resizable().scaledToFit().frame(width: 39, height: 15)
                .padding(.horizontal, dark ? 4 : 0).padding(.vertical, dark ? 2 : 0)
                .background(dark ? Color(red: 1, green: 0.96, blue: 0.86) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
            Spacer(minLength: 3)
            Text(title).font(.system(size: isSmall ? 10 : 11, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func small(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            ZStack(alignment: .trailing) {
                characters.frame(width: size.width * 0.58, height: size.height - 50)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        metric(compact: true)
                        Text(subtitle).font(.system(size: 10, weight: .medium))
                            .lineLimit(topic == .reorder || topic == .lab ? 3 : 2)
                    }.frame(width: size.width * 0.39, alignment: .leading)
                    Spacer(minLength: 0)
                }
            }.frame(maxHeight: .infinity)
            if topic == .stamps { stampDots(compact: true) }
            footer
        }
    }

    /// Prominent artwork, a trailing header, and a compact information group.
    private func mediumStreak(size: CGSize) -> some View {
        let honey = Color(red: 0.91, green: 0.64, blue: 0.16)
        let timed = snapshot.streak
        let count = timed.flatMap { $0.value.currentCount(at: entry.date, fetchedAt: $0.fetchedAt) }
        return HStack(spacing: 0) {
            mediumCharacter(size: CGSize(width: size.width * 0.38, height: size.height))
            VStack(alignment: .leading, spacing: 2) {
                mediumHeader(size: size)
                HStack(alignment: .bottom, spacing: 7) {
                    Text(count.map { $0.formatted() } ?? "—")
                        .font(.system(size: 50, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.55).widgetAccentable()
                        .accessibilityLabel(title + ": " + (count.map(String.init) ?? widgetCopy("Update needed", "Cần cập nhật")))
                    VStack(alignment: .leading, spacing: 1) {
                        Image(systemName: "flame.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(honey).accessibilityHidden(true)
                        Text(widgetCopy("DAYS", "NGÀY")).font(.system(size: 14, weight: .bold, design: .rounded))
                    }.padding(.bottom, 7)
                    Spacer(minLength: 0)
                }.frame(height: 51, alignment: .leading)
                if let streak = timed?.value {
                    HStack(spacing: 3) {
                        ForEach(-6...0, id: \.self) { offset in
                            let date = streak.calendar().date(byAdding: .day, value: offset, to: entry.date)!
                            let known = streak.knownOrderDays.contains(streak.dayKey(date))
                            VStack(spacing: 2) {
                                ZStack {
                                    if known {
                                        Circle().fill(honey)
                                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                                    } else {
                                        Circle().strokeBorder(ink.opacity(0.25), lineWidth: 1)
                                        Text("?").font(.system(size: 8, weight: .medium)).foregroundStyle(ink.opacity(0.55))
                                    }
                                }.frame(width: 17, height: 17)
                                Text(streak.calendar().veryShortWeekdaySymbols[streak.calendar().component(.weekday, from: date) - 1])
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                            }.frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(streak.dayKey(date) + ": " + (known ? widgetCopy("completed order", "có đơn hoàn tất") : widgetCopy("history unavailable", "chưa có dữ liệu")))
                        }
                    }.padding(.top, 1)
                        .offset(x: -8)
                }
                if isStale || count == nil {
                    mediumCaption(widgetCopy("Open MyFitbites to update", "Mở MyFitbites để cập nhật"))
                } else if entry.configuration.comments && !typeSize.isAccessibilitySize {
                    mediumCaption(comment, isCharacterComment: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 12)
        }.frame(width: size.width, height: size.height)
    }

    private func mediumCharacter(size: CGSize) -> some View {
        Group {
            if companion == .tiel {
                // Measured alpha bounds of the approved PNGs, not a stretched/cropped character.
                // Remove transparent canvas padding from layout so the crest and claws reach the edges.
                let bounds: CGRect = {
                    switch tielAsset {
                    case "tiel_streak_wings_crossed": return CGRect(x: 227, y: 28, width: 804, height: 1302)
                    case "tiel_streak_tiny_dinosaur": return CGRect(x: 108, y: 25, width: 915, height: 1306)
                    case "tiel_guarding_cookies": return CGRect(x: 132, y: 23, width: 881, height: 1312)
                    case "tiel_welcome_back": return CGRect(x: 181, y: 17, width: 856, height: 1298)
                    default: return CGRect(x: 222, y: 48, width: 772, height: 1277)
                    }
                }()
                let feetCenterX: CGFloat = {
                    switch tielAsset {
                    case "tiel_streak_wings_crossed": return 577
                    case "tiel_streak_tiny_dinosaur": return 596
                    case "tiel_guarding_cookies": return 603.5
                    case "tiel_welcome_back": return 580.5
                    default: return 556
                    }
                }()
                let scale = (size.height - 4) / bounds.height
                // Register every pose to the approved pose's feet, not the tail's silhouette width.
                let feetAnchor = (size.height - 4) * (-52.0 / 1277.0)
                character(tielAsset)
                    .frame(width: 1145 * scale, height: 1374 * scale)
                    .offset(x: (572.5 - feetCenterX) * scale + feetAnchor, y: (687 - bounds.midY) * scale)
                    .frame(width: size.width, height: size.height)
            } else if companion == .too && topic == .stamps {
                // Register the original PNGs by their visible crest/feet, preserving proportions.
                let registration: (canvas: CGSize, bounds: CGRect, feetX: CGFloat) = {
                    switch tooAsset {
                    case "too_cookie_jar": return (CGSize(width: 1202, height: 1308), CGRect(x: 219, y: 22, width: 781, height: 1258), 653.5)
                    case "too_reward_celebration": return (CGSize(width: 1202, height: 1309), CGRect(x: 150, y: 45, width: 961, height: 1214), 669.5)
                    default: return (CGSize(width: 1122, height: 1402), CGRect(x: 104, y: 46, width: 974, height: 1319), 598)
                    }
                }()
                let scale = min((size.height - 4) / registration.bounds.height, (size.width - 4) / registration.bounds.width)
                let leftReach = (registration.feetX - registration.bounds.minX) * scale
                let rightReach = (registration.bounds.maxX - registration.feetX) * scale
                let feetX = min(size.width - rightReach - 2, max(leftReach + 2, size.width * 0.53))
                character(tooAsset)
                    .frame(width: registration.canvas.width * scale, height: registration.canvas.height * scale)
                    .offset(x: (registration.canvas.width / 2 - registration.feetX) * scale + feetX - size.width / 2,
                            y: (registration.canvas.height / 2 - registration.bounds.midY) * scale)
                    .frame(width: size.width, height: size.height)
            } else {
                characters.frame(width: size.width, height: size.height * 0.96)
            }
        }.accessibilityHidden(true)
    }

    private func mediumCaption(_ text: String, isCharacterComment: Bool = false) -> some View {
        let speaker = companion == .too ? "Too" : "Tiel"
        let caption = isCharacterComment ? "\(speaker): '\(text)'" : text
        let shortCaption = isCharacterComment
            ? "\(speaker): '\(widgetCopy("Keep going.", "Cứ tiếp tục nhé."))'"
            : widgetCopy("Open app to update", "Mở ứng dụng để cập nhật")
        return ViewThatFits(in: .horizontal) {
            Text(caption).fixedSize(horizontal: true, vertical: false)
            Text(shortCaption)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .lineLimit(1).padding(.vertical, 4)
        .padding(.top, 3)
        .accessibilityLabel(caption)
    }

    private let mediumHoney = Color(red: 0.91, green: 0.64, blue: 0.16)

    private func mediumTrailingInset(_ size: CGSize) -> CGFloat {
        let informationWidth = size.width * 0.62 - 5 - 14
        let dayCellWidth = (informationWidth - 6 * 3) / 7
        return 8 + max(0, (dayCellWidth - 17) / 2)
    }

    private var mediumHeading: String {
        switch topic {
        case .streak: widgetCopy("ORDER STREAK", "CHUỖI ĐẶT MÓN")
        case .cookies: "B COOKIES"
        case .stamps: widgetCopy("LOYALTY CARD", "THẺ TÍCH ĐIỂM")
        case .reorder: widgetCopy("ORDER AGAIN", "ĐẶT LẠI MÓN")
        case .lab: "TOO’S LAB"
        case .today: "TODAY AT FITBITES"
        }
    }

    private func mediumHeader(size: CGSize) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Image("FitbitesLogo").resizable().interpolation(.high).scaledToFit().frame(width: 74, height: 18)
                .padding(.horizontal, dark ? 4 : 0)
                .background(dark ? Color(red: 1, green: 0.96, blue: 0.86) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
            Text(mediumHeading)
                .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(0.6)
                .lineLimit(1).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 74)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, mediumTrailingInset(size))
    }

    private func mediumLoyalty(size: CGSize) -> some View {
        HStack(spacing: 0) {
            mediumCharacter(size: CGSize(width: size.width * 0.38, height: size.height))
            VStack(alignment: .leading, spacing: 3) {
                mediumHeader(size: size)
                if let loyalty = snapshot.loyalty?.value {
                    Group {
                        if loyalty.rewardReady && !isStale {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(widgetCopy("CLAIM YOUR", "NHẬN NGAY"))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Text(widgetCopy("FREE FITBITES", "FITBITES MIỄN PHÍ"))
                                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                                    .lineLimit(1).minimumScaleFactor(0.75)
                            }.accessibilityElement(children: .combine)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(loyalty.stamps.formatted())
                                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("/ \(loyalty.target)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Text(widgetCopy("STAMPS", "TEM"))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }.lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }.frame(height: 40, alignment: .leading)
                    cookieStamps(loyalty, height: 23, completedCard: !isStale && loyalty.rewardReady)
                        .padding(.trailing, mediumTrailingInset(size))
                    if isStale {
                        Text(widgetCopy("Open MyFitbites to update", "Mở MyFitbites để cập nhật"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .frame(height: 35, alignment: .topLeading)
                    } else if entry.configuration.comments && !typeSize.isAccessibilitySize {
                        Text("Too: '\(loyalty.tooComment)'")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .frame(height: 35, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 12)
        }.frame(width: size.width, height: size.height)
    }

    private func cookieStamps(_ loyalty: WidgetSnapshot.Loyalty, height: CGFloat, completedCard: Bool = false) -> some View {
        let count = completedCard ? loyalty.displayedCardStamps : max(0, min(loyalty.target, loyalty.stamps))
        return HStack(spacing: 2) {
            ForEach(0..<min(12, max(1, loyalty.target)), id: \.self) { index in
                Group {
                    if index < count {
                        character("BCookieStamp")
                    } else {
                        Image("BCookieStamp").resizable().renderingMode(.template).scaledToFit()
                            .foregroundStyle(ink.opacity(dark ? 0.22 : 0.10))
                    }
                }.frame(maxWidth: .infinity).frame(height: height)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(completedCard
                ? widgetCopy("Completed card. Free Fitbites ready to claim.", "Thẻ đã đủ tem. Nhận Fitbites miễn phí.")
                : widgetCopy("\(loyalty.stamps) of \(loyalty.target) B-cookie stamps", "\(loyalty.stamps) trên \(loyalty.target) tem B cookie"))
    }

    private func medium(size: CGSize) -> some View {
        HStack(spacing: 0) {
            mediumCharacter(size: CGSize(width: size.width * 0.38, height: size.height))
            VStack(alignment: .leading, spacing: 2) {
                mediumHeader(size: size)
                mediumMetric.frame(height: 51, alignment: .leading)
                mediumDetails
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, mediumTrailingInset(size))
                    .frame(height: 29, alignment: .center)
                if isStale {
                    mediumCaption(widgetCopy("Open MyFitbites to update", "Mở MyFitbites để cập nhật"))
                } else if entry.configuration.comments && !typeSize.isAccessibilitySize {
                    mediumCaption(comment, isCharacterComment: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 12)
        }.frame(width: size.width, height: size.height)
    }

    private func mediumUnavailable(_ text: String, size: CGSize) -> some View {
        HStack(spacing: 0) {
            mediumCharacter(size: CGSize(width: size.width * 0.38, height: size.height))
            VStack(alignment: .leading, spacing: 2) {
                mediumHeader(size: size)
                Text(text).font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(3).minimumScaleFactor(0.8)
                    .frame(height: 82, alignment: .leading)
                mediumCaption(widgetCopy("Your companions are ready.", "Too và Tiel đang đợi bạn."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 12)
        }.frame(width: size.width, height: size.height)
    }

    @ViewBuilder private var mediumMetric: some View {
        switch topic {
        case .cookies:
            HStack(alignment: .bottom, spacing: 7) {
                mediumNumber(snapshot.loyalty?.value.stamps.formatted() ?? "—")
                Text(widgetCopy("STAMPS", "TEM")).font(.system(size: 14, weight: .bold, design: .rounded)).padding(.bottom, 7)
            }
        case .stamps:
            HStack(alignment: .bottom, spacing: 4) {
                mediumNumber(snapshot.loyalty?.value.stamps.formatted() ?? "—")
                Text("/ \(snapshot.loyalty?.value.target ?? 9)")
                    .font(.system(size: 22, weight: .bold, design: .rounded)).padding(.bottom, 7)
            }
        case .reorder:
            Text(widgetCopy("Again?", "Đặt lại?"))
                .font(.system(size: 36, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
        case .lab:
            if let lab = snapshot.lab?.value, lab.unlocked { mediumNumber(lab.clearance) }
            else {
                Text(widgetCopy("Locked", "Chưa mở"))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
            }
        case .streak, .today: EmptyView()
        }
    }

    private func mediumNumber(_ number: String) -> some View {
        Text(number).font(.system(size: 50, weight: .bold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55).widgetAccentable()
            .accessibilityLabel(title + ": " + number)
    }

    @ViewBuilder private var mediumDetails: some View {
        switch topic {
        case .cookies:
            if let loyalty = snapshot.loyalty?.value {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(mediumHoney.opacity(0.18))
                            Capsule().fill(mediumHoney)
                                .frame(width: proxy.size.width * min(1, max(0, Double(loyalty.stamps) / Double(max(1, loyalty.target)))))
                        }
                    }.frame(height: 4)
                        .accessibilityLabel(widgetCopy("\(loyalty.stamps) of \(loyalty.target) stamps", "\(loyalty.stamps) trên \(loyalty.target) tem"))
                    Text(widgetCopy("\(max(0, loyalty.target - loyalty.stamps)) to your next free Fitbites", "Còn \(max(0, loyalty.target - loyalty.stamps)) tem đến phần thưởng"))
                        .font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        case .stamps:
            if let loyalty = snapshot.loyalty?.value {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        ForEach(0..<min(12, max(1, loyalty.target)), id: \.self) { index in
                            if index > 0 { Spacer(minLength: 2) }
                            ZStack {
                                if index < loyalty.stamps {
                                    Circle().fill(mediumHoney)
                                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                                } else { Circle().strokeBorder(ink.opacity(0.25), lineWidth: 1) }
                            }.frame(width: 13, height: 13)
                        }
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel(widgetCopy("\(loyalty.stamps) of \(loyalty.target) stamps", "\(loyalty.stamps) trên \(loyalty.target) tem"))
                    Text(loyalty.rewards > 0
                         ? widgetCopy(loyalty.rewards == 1 ? "1 free reward ready" : "\(loyalty.rewards) free rewards ready", "Có \(loyalty.rewards) phần thưởng miễn phí")
                         : widgetCopy("\(max(0, loyalty.target - loyalty.stamps)) to your next free Fitbites", "Còn \(max(0, loyalty.target - loyalty.stamps)) tem đến phần thưởng"))
                        .font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        case .reorder:
            VStack(alignment: .leading, spacing: 3) {
                Text(subtitle).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(widgetCopy("Tap to review", "Chạm để xem lại")).font(.system(size: 9, weight: .medium))
            }
        case .lab:
            Text(subtitle).font(.system(size: 11, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.85)
        case .streak, .today: EmptyView()
        }
    }

    private func large(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .center, spacing: 16) {
                characters.frame(width: size.width * 0.45, height: size.height * 0.48)
                VStack(alignment: .leading, spacing: 6) {
                    metric(compact: false)
                    Text(largeSubtitle).font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if topic == .streak, let streak = snapshot.streak?.value {
                        Text(widgetCopy("Best: ", "Kỷ lục: ") + "\(streak.longest)").font(.caption).opacity(0.75)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            detail(compact: false)
            Spacer(minLength: 0)
            if entry.configuration.comments && !typeSize.isAccessibilitySize && !isStale {
                Text(comment).font(.system(.caption, design: .rounded, weight: .medium)).lineLimit(2)
            }
            footer
        }
    }

    private func empty(_ text: String, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            HStack(spacing: 10) {
                characters.frame(width: isSmall ? size.width * 0.38 : size.width * 0.32, height: isLarge ? 190 : max(60, size.height - 73))
                Text(text).font(.system(isSmall ? .caption : .headline, design: .rounded, weight: .semibold)).lineLimit(3)
            }.frame(maxHeight: .infinity)
            Text(widgetCopy("Your companions are ready.", "Too và Tiel đang đợi bạn.")).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func metric(compact: Bool) -> some View {
        let number: String = {
            switch topic {
            case .streak: return snapshot.streak.flatMap { $0.value.currentCount(at: entry.date, fetchedAt: $0.fetchedAt) }.map { $0.formatted() } ?? "—"
            case .cookies: return snapshot.loyalty?.value.stamps.formatted() ?? "—"
            case .today: return ""
            case .stamps: return snapshot.loyalty.map { "\($0.value.stamps)/\($0.value.target)" } ?? "—"
            case .reorder: return widgetCopy("Again?", "Đặt lại?")
            case .lab: return snapshot.lab?.value.unlocked == true ? snapshot.lab!.value.clearance : widgetCopy("Level 5", "Cấp 5")
            }
        }()
        Text(number)
            .font(.system(size: compact ? 32 : (topic == .reorder || topic == .lab ? 26 : 42), weight: .bold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .widgetAccentable()
            .accessibilityLabel(title + ": " + number)
    }

    private var largeSubtitle: String {
        switch topic {
        case .lab: return snapshot.lab?.value.unlocked == true ? widgetCopy("Unlocked experiments", "Thí nghiệm đã mở") : subtitle
        case .reorder: return widgetCopy("Ready to review", "Sẵn sàng để xem lại")
        case .stamps: return widgetCopy("B cookies collected", "B cookie đã tích lũy")
        default: return subtitle
        }
    }

    private var subtitle: String {
        switch topic {
        case .today: return ""
        case .streak: return widgetCopy("consecutive days", "ngày liên tiếp")
        case .cookies: return widgetCopy("loyalty stamps", "tem tích điểm")
        case .stamps:
            guard let v = snapshot.loyalty?.value else { return "" }
            return widgetCopy("\(max(0, v.target - v.stamps)) to your next free Fitbites", "Còn \(max(0, v.target - v.stamps)) tem đến phần thưởng")
        case .reorder:
            return isStale ? widgetCopy("Open to refresh", "Mở để cập nhật") : (snapshot.orders?.value.first?.name ?? widgetCopy("Find a new favourite", "Tìm món yêu thích mới"))
        case .lab:
            guard let lab = snapshot.lab?.value, lab.unlocked else { return widgetCopy("Your lab awaits", "Phòng lab chờ bạn") }
            return isStale ? widgetCopy("Open to refresh", "Mở để cập nhật") : (lab.discoveries.first?.name ?? widgetCopy("Build your clearance", "Nâng cấp quyền truy cập"))
        }
    }

    @ViewBuilder private func detail(compact: Bool) -> some View {
        switch topic {
        case .today: EmptyView()
        case .streak:
            dayMarkers
            if !compact, let timed = snapshot.streak, let current = timed.value.currentCount(at: entry.date, fetchedAt: timed.fetchedAt) {
                let next = [(2,5),(3,10),(4,15),(5,20),(6,50)].first { $0.0 > current }
                if let next {
                    ProgressView(value: Double(current), total: Double(next.0)).tint(gold)
                    Text(widgetCopy("\(next.0) days → +\(next.1)% order XP", "\(next.0) ngày → +\(next.1)% XP đặt món")).font(.system(size: 12, weight: .semibold))
                } else { Text(widgetCopy("Maximum streak XP bonus reached", "Đã đạt mức thưởng XP chuỗi tối đa")).font(.caption) }
            }
        case .cookies:
            if let loyalty = snapshot.loyalty?.value {
                ProgressView(value: Double(loyalty.stamps), total: Double(loyalty.target)).tint(gold)
                Text(widgetCopy("\(max(0, loyalty.target - loyalty.stamps)) more B cookies to a free Fitbites", "Còn \(max(0, loyalty.target - loyalty.stamps)) B cookie đến phần thưởng Fitbites"))
                    .font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(2)
                if !compact {
                    stampDots(compact: false)
                    Label(widgetCopy("\(loyalty.rewards) free rewards ready", "Có \(loyalty.rewards) phần thưởng miễn phí"), systemImage: "gift").font(.system(size: 12, weight: .semibold))
                }
            }
        case .stamps:
            stampDots(compact: compact)
            Text(subtitle).font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(2)
            if !compact, let v = snapshot.loyalty?.value, v.rewards > 0 {
                Label(widgetCopy(v.rewards == 1 ? "1 reward ready" : "\(v.rewards) rewards ready", "Có \(v.rewards) phần thưởng"), systemImage: "gift").font(.system(size: 12, weight: .semibold))
            }
        case .reorder:
            if isStale { Text(widgetCopy("Open to refresh your orders", "Mở để cập nhật đơn hàng")).font(.caption) }
            else if compact { Text(subtitle).font(.system(size: 12, weight: .semibold)).lineLimit(2); reviewHint }
            else {
                ForEach(Array((snapshot.orders?.value ?? []).prefix(3))) { order in
                    Link(destination: WidgetRoute(topic: .reorder, itemID: String(order.id), sessionID: snapshot.sessionID).url) {
                        HStack(spacing: 9) {
                            Image(systemName: "bag").frame(width: 22).accessibilityHidden(true)
                            Text(order.name).lineLimit(2)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.font(.system(size: 12, weight: .semibold))
                    }
                }
                reviewHint
            }
        case .lab:
            if snapshot.lab?.value.unlocked != true {
                Text(widgetCopy("Keep exploring MyFitbites. No locked experiments are shown here.", "Tiếp tục khám phá MyFitbites. Các thí nghiệm bị khóa được giữ kín.")).font(.caption).lineLimit(compact ? 2 : 3)
            } else if isStale { Text(widgetCopy("Open the lab to update clearance", "Mở phòng lab để cập nhật quyền truy cập")).font(.caption) }
            else if compact { Text(subtitle).font(.system(size: 12, weight: .semibold)).lineLimit(2) }
            else {
                ForEach(Array((snapshot.lab?.value.discoveries ?? []).prefix(2))) { discovery in
                    Link(destination: WidgetRoute(topic: .lab, itemID: discovery.id, sessionID: snapshot.sessionID).url) {
                        HStack(spacing: 10) {
                            Image(discovery.imageName).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                            Text(discovery.name).lineLimit(2).font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 2)
                            Text(discovery.clearance).font(.caption2.bold())
                        }
                    }
                }
                if snapshot.lab?.value.discoveries.isEmpty == true { Text(widgetCopy("Play experiments to build Lab XP", "Chơi thí nghiệm để tích lũy Lab XP")).font(.caption) }
            }
        }
    }

    private var reviewHint: some View {
        Text(widgetCopy("Tap to review · no automatic order", "Chạm để xem · không tự đặt món")).font(.system(size: 10)).opacity(0.8).lineLimit(2)
    }
    private var footer: some View {
        HStack(spacing: 3) {
            if isStale { Image(systemName: "arrow.clockwise").font(.system(size: 8)) }
            Text(isStale ? widgetCopy("Saved · open to refresh", "Đã lưu · mở để cập nhật") : widgetCopy("From your last app sync", "Từ lần cập nhật ứng dụng"))
                .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }.opacity(0.75)
    }

    private func stampDots(compact: Bool) -> some View {
        cookieStamps(snapshot.loyalty?.value ?? .init(stamps: 0, target: 9, rewards: 0), height: compact ? 16 : 27)
    }

    private var dayMarkers: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let streak = snapshot.streak?.value {
                HStack(spacing: 3) {
                    ForEach(-6...0, id: \.self) { offset in
                        let date = streak.calendar().date(byAdding: .day, value: offset, to: entry.date)!
                        let known = streak.knownOrderDays.contains(streak.dayKey(date))
                        VStack(spacing: 3) {
                            Text(streak.calendar().veryShortWeekdaySymbols[streak.calendar().component(.weekday, from: date) - 1])
                                .font(.system(size: 8, weight: .semibold))
                            Image(systemName: known ? "checkmark.circle.fill" : "minus.circle")
                                .font(.system(size: 14)).foregroundStyle(known ? gold : ink.opacity(0.3))
                        }.frame(maxWidth: .infinity)
                            .accessibilityLabel(streak.dayKey(date) + ": " + (known ? widgetCopy("completed order", "có đơn hoàn tất") : widgetCopy("history unavailable", "chưa có dữ liệu")))
                    }
                }
                Text(widgetCopy("Recent orders · – unknown", "Đơn gần đây · – chưa rõ")).font(.system(size: 8)).opacity(0.7)
            }
        }
    }

    private var tielAsset: String {
        guard topic == .streak, unavailableText == nil, !isStale else { return "tiel_welcome_back" }
        return snapshot.streak?.value.tielPose(at: entry.date) ?? "tiel_welcome_back"
    }
    private var tooAsset: String {
        guard unavailableText == nil else { return "too_welcome" }
        switch topic {
        case .cookies: return "too_cookie_jar"
        case .stamps:
            // A stale reward must not keep celebrating a claim we can no longer confirm.
            if isStale { return (snapshot.loyalty?.value.stamps ?? 0) > 0 ? "too_cookie_jar" : "too_welcome" }
            return snapshot.loyalty?.value.tooPose ?? "too_welcome"
        case .lab: return "too_lab_discovery"
        default: return "too_welcome"
        }
    }
    private var characters: some View {
        GeometryReader { proxy in
            if companion == .both {
                let half = (proxy.size.width + 4) / 2
                HStack(alignment: .bottom, spacing: -4) {
                    character(tooAsset).frame(width: half, height: proxy.size.height, alignment: .bottom)
                    character(tielAsset).frame(width: half * 0.80, height: proxy.size.height * 0.80, alignment: .bottom)
                        .frame(width: half, height: proxy.size.height, alignment: .bottom)
                }
            } else {
                character(companion == .too ? tooAsset : tielAsset)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }.accessibilityHidden(true)
    }
    @ViewBuilder private func character(_ name: String) -> some View {
        if #available(iOS 18.0, *) {
            Image(name).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else { Image(name).resizable().scaledToFit() }
    }
    private var comment: String {
        if companion == .too {
            if topic == .stamps, let loyalty = snapshot.loyalty?.value { return loyalty.tooComment }
            return topic == .lab ? widgetCopy("A little curiosity goes a long way.", "Một chút tò mò, thật nhiều khám phá.") : widgetCopy("Always happy to see you.", "Lúc nào cũng vui khi gặp bạn.")
        }
        if topic == .streak, let s = snapshot.streak?.value {
            if s.returning && s.daysSinceOrder(at: entry.date) == 0 { return widgetCopy("I never doubted you.", "Tôi chưa từng nghi ngờ bạn.") }
            switch s.missedOrderDays(at: entry.date) {
            case 0: return widgetCopy("Acceptable. Keep going.", "Cũng được. Cứ thế nhé.")
            case 1: return widgetCopy("One day missed. Really?", "Nghỉ một ngày rồi đấy?")
            case 2: return widgetCopy("Two days? Really?", "Hai ngày rồi sao?")
            case .some(3...): return widgetCopy("I'm keeping these.", "Tôi giữ chỗ này nhé.")
            default: break
            }
        }
        return widgetCopy("Good to have you back.", "Thật vui khi bạn quay lại.")
    }
}

/// One daily editorial card, using the same white composition as Streak and Loyalty.
struct TodayAtFitbitesView: View {
    let entry: FitbitesEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var typeSize
    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var kind: WidgetTodayKind? { snapshot.todayKind(preferred: entry.todayPreference, at: entry.date) }
    private var dark: Bool { entry.configuration.appearance == .espresso || (entry.configuration.appearance == .system && colorScheme == .dark) }
    private var ink: Color { renderingMode == .fullColor ? (dark ? Color(red: 1, green: 0.94, blue: 0.81) : Color(red: 0.24, green: 0.15, blue: 0.10)) : .primary }
    private var honey: Color { Color(red: 0.91, green: 0.64, blue: 0.16) }
    private var route: WidgetRoute {
        let item: String?
        switch kind {
        case .lab: item = snapshot.lab?.value.discoveries.first.map { "lab-" + $0.id }
        case .member: item = "member"
        case .recipe: item = snapshot.recipe.map { "recipe-" + $0.value.productID }
        case .arcade: item = "arcade"
        case nil: item = nil
        }
        return WidgetRoute(topic: .today, itemID: item, sessionID: snapshot.sessionID)
    }
    private var art: String {
        switch kind ?? entry.todayPreference {
        case .lab: "today_too_scientist"
        case .member: "today_tiel_audit"
        case .recipe: "today_too_chef"
        case .arcade: "today_rico_arcade"
        case nil: "today_tiel_announcement"
        }
    }
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                artwork(size: CGSize(width: proxy.size.width * 0.38, height: proxy.size.height))
                VStack(alignment: .leading, spacing: 4) {
                    brand
                    if let kind {
                        information(kind).frame(height: 83, alignment: .topLeading)
                        if let fetched = snapshot.todayFetchedAt(kind), entry.date.timeIntervalSince(fetched) >= 6 * 3600 {
                            Text(widgetCopy("Updated ", "Cập nhật ") + fetched.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .frame(height: 16, alignment: .leading)
                        } else if entry.configuration.comments && !typeSize.isAccessibilitySize {
                            Text(comment(kind))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.85)
                                .frame(height: 16, alignment: .leading)
                        }
                    } else {
                        Text(snapshot.status == .signedOut
                             ? widgetCopy("Sign in to MyFitbites", "Đăng nhập MyFitbites")
                             : widgetCopy("Open MyFitbites for today’s updates", "Mở MyFitbites để xem cập nhật hôm nay"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .lineLimit(3).minimumScaleFactor(0.8)
                            .frame(height: 103, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(ink).fontDesign(.rounded)
        .containerBackground(for: .widget) { Color(dark ? .init(red: 0.15, green: 0.10, blue: 0.08, alpha: 1) : .white) }
        .widgetURL(route.url).privacySensitive()
    }
    private var brand: some View {
        VStack(alignment: .center, spacing: 2) {
            Image("FitbitesLogo").resizable().interpolation(.high).scaledToFit().frame(width: 74, height: 18)
                .background(dark ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 4)).accessibilityHidden(true)
            Text(widgetCopy("TODAY AT FITBITES", "HÔM NAY TẠI FITBITES"))
                .font(.system(size: 7.7, weight: .semibold, design: .rounded)).tracking(0.2)
                .lineLimit(1).minimumScaleFactor(0.8)
        }.frame(width: 84).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10)
    }
    @ViewBuilder private func information(_ kind: WidgetTodayKind) -> some View {
        switch kind {
        case .member:
            if let member = snapshot.member?.value {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(member.level.formatted()).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(widgetCopy("LEVEL", "CẤP")).font(.system(size: 11, weight: .bold, design: .rounded))
                    }.frame(height: 39, alignment: .leading)
                    Text(member.tier).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(honey.opacity(0.18))
                            Capsule().fill(honey).frame(width: proxy.size.width * member.progress)
                        }
                    }.frame(height: 5).padding(.trailing, 10).accessibilityHidden(true)
                    Text(member.isMaximumLevel ? widgetCopy("Maximum level reached", "Đã đạt cấp cao nhất") : "\(member.levelXP.formatted()) / \(member.levelTarget.formatted()) XP")
                        .font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
                }.accessibilityElement(children: .combine)
            }
        case .lab:
            if let discovery = snapshot.lab?.value.discoveries.first {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(widgetCopy("TOO’S CREATIONS", "SÁNG TẠO CỦA TOO"))
                    Text(discovery.name.localizedCapitalized)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .lineLimit(1).truncationMode(.tail)
                    Text(widgetCopy("Explore in Too’s Lab", "Khám phá trong Too’s Lab"))
                        .font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1)
                }
            }
        case .recipe:
            if let recipe = snapshot.recipe?.value {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(recipe.eyebrow.uppercased())
                    headline(recipe.name)
                    if recipe.name.count <= 30 {
                        Text(widgetCopy("Fresh from our kitchen", "Mới từ bếp Fitbites"))
                            .font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1)
                    }
                }
            }
        case .arcade:
            if let arcade = snapshot.arcade?.value {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow("MY ARCADE")
                    Text(widgetCopy("Press Start", "Nhấn bắt đầu"))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text(widgetCopy(arcade.credits == 1 ? "1 credit available" : "\(arcade.credits) credits available", "Còn \(arcade.credits) lượt chơi"))
                        .font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1)
                }
            }
        }
    }
    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(0.5)
            .lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(ink.opacity(0.75))
    }
    private func headline(_ text: String) -> some View {
        let expanded = text.count > 30
        return Text(text).font(.system(size: expanded ? 17 : 23, weight: .bold, design: .rounded))
            .lineLimit(expanded ? 3 : 2).minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func comment(_ kind: WidgetTodayKind) -> String {
        switch kind {
        case .lab: widgetCopy("Too: 'Science tastes good.'", "Too: 'Khoa học thật ngon.'")
        case .member: widgetCopy("Tiel: 'Progress noted.'", "Tiel: 'Đã ghi nhận tiến bộ.'")
        case .recipe: widgetCopy("Too: 'I made you something.'", "Too: 'Tôi làm món này cho bạn.'")
        case .arcade: widgetCopy("Rico: 'Try to keep up.'", "Rico: 'Cố theo kịp nhé.'")
        }
    }
    private func artwork(size: CGSize) -> some View {
        let registration: (canvas: CGSize, bounds: CGRect, feetX: CGFloat) = {
            switch art {
            case "today_too_scientist": return (CGSize(width: 1145, height: 1374), CGRect(x: 122, y: 65, width: 966, height: 1266), 612.5)
            case "today_tiel_audit": return (CGSize(width: 1145, height: 1374), CGRect(x: 182, y: 23, width: 859, height: 1317), 568)
            case "today_too_chef": return (CGSize(width: 1145, height: 1374), CGRect(x: 62, y: 15, width: 1070, height: 1339), 589.5)
            case "today_rico_arcade": return (CGSize(width: 1024, height: 1536), CGRect(x: 49, y: 100, width: 955, height: 1349), 626.5)
            default: return (CGSize(width: 1145, height: 1374), CGRect(x: 25, y: 18, width: 1079, height: 1330), 633)
            }
        }()
        let scale = min((size.height - 4) / registration.bounds.height, (size.width - 4) / registration.bounds.width)
        let leftReach = (registration.feetX - registration.bounds.minX) * scale
        let rightReach = (registration.bounds.maxX - registration.feetX) * scale
        let feetX = min(size.width - rightReach - 2, max(leftReach + 2, size.width * 0.53))
        return artworkImage
            .frame(width: registration.canvas.width * scale, height: registration.canvas.height * scale)
            .offset(x: (registration.canvas.width / 2 - registration.feetX) * scale + feetX - size.width / 2,
                    y: (registration.canvas.height / 2 - registration.bounds.midY) * scale)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
    @ViewBuilder private var artworkImage: some View {
        if #available(iOS 18.0, *) { Image(art).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit() }
        else { Image(art).resizable().scaledToFit() }
    }
}


/// The one large family: membership, the real B-cookie card, and a recent order.
struct MyFitbitesOverviewView: View {
    let entry: FitbitesEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var ink: Color { renderingMode == .fullColor ? Color(red: 0.24, green: 0.15, blue: 0.10) : .primary }
    private let honey = Color(red: 0.91, green: 0.64, blue: 0.16)
    private var memberRoute: URL { WidgetRoute(topic: .today, itemID: "member", sessionID: snapshot.sessionID).url }
    private var loyaltyRoute: URL { WidgetRoute(topic: .stamps, sessionID: snapshot.sessionID).url }
    private var freshOrder: WidgetSnapshot.Reorder? {
        guard snapshot.status == .ready, let orders = snapshot.orders, !orders.isStale(at: entry.date) else { return nil }
        return orders.value.first
    }
    private var orderRoute: URL { WidgetRoute(topic: .reorder, itemID: freshOrder.map { String($0.id) }, sessionID: snapshot.sessionID).url }

    var body: some View {
        GeometryReader { proxy in
            let sectionHeight = max(0, proxy.size.height - 32 - 24 - 40 - 2)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    stampImage.frame(width: 20, height: 22).accessibilityHidden(true)
                    Text("MYFITBITES").font(.system(size: 16, weight: .heavy, design: .rounded)).tracking(1.2)
                    Spacer(minLength: 0)
                }.frame(height: 24)
                if snapshot.status == .ready {
                    Link(destination: memberRoute) { memberSection(height: sectionHeight * 0.31) }
                    separator
                    Link(destination: loyaltyRoute) { loyaltySection(height: sectionHeight * 0.40) }
                    separator
                    Link(destination: orderRoute) { reorderSection(height: sectionHeight * 0.29) }
                } else {
                    VStack(spacing: 12) {
                        registeredArt("too_welcome", width: 136, height: sectionHeight * 0.65)
                        Text(snapshot.status == .signedOut ? widgetCopy("Sign in to MyFitbites", "Đăng nhập MyFitbites") : widgetCopy("Open MyFitbites to update", "Mở MyFitbites để cập nhật"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                        Text(widgetCopy("Your level, rewards and favourites, together.", "Cấp độ, phần thưởng và món yêu thích của bạn."))
                            .font(.system(size: 11, design: .rounded)).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.padding(16)
        }
        .buttonStyle(.plain).foregroundStyle(ink).fontDesign(.rounded)
        .containerBackground(for: .widget) { Color.white }
        .widgetURL(memberRoute).privacySensitive()
    }
    private var separator: some View { Rectangle().fill(ink.opacity(0.10)).frame(height: 1) }
    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(0.6).lineLimit(1)
    }
    private func updateHint(_ stamp: Date) -> String {
        widgetCopy("Updated ", "Cập nhật ") + stamp.formatted(date: .omitted, time: .shortened)
    }
    private func memberSection(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            registeredArt("today_tiel_audit", width: 80, height: height)
            VStack(alignment: .leading, spacing: 4) {
                if let member = snapshot.member, !member.isExpiredForToday(at: entry.date) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(member.value.level.formatted()).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                        label(widgetCopy("LEVEL", "CẤP"))
                    }.frame(height: 31, alignment: .leading)
                    Text(member.value.tier).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(honey.opacity(0.18))
                            Capsule().fill(honey).frame(width: proxy.size.width * member.value.progress)
                        }
                    }.frame(height: 5).accessibilityHidden(true)
                    Text(member.value.isMaximumLevel ? widgetCopy("Maximum level reached", "Đã đạt cấp cao nhất") : "\(member.value.levelXP.formatted()) / \(member.value.levelTarget.formatted()) XP")
                        .font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
                    if member.isStale(at: entry.date) { Text(updateHint(member.fetchedAt)).font(.system(size: 8, design: .rounded)).lineLimit(1) }
                } else {
                    label(widgetCopy("LEVEL & XP", "CẤP ĐỘ & XP"))
                    Text(widgetCopy("Open to update your progress", "Mở để cập nhật tiến độ"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: height).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private func loyaltySection(height: CGFloat) -> some View {
        let timed = snapshot.loyalty
        let usable = timed.map { !$0.isExpiredForToday(at: entry.date) } ?? false
        let rewardReady = usable && timed?.value.rewardReady == true && timed?.isStale(at: entry.date) == false
        let pose = !usable ? "too_welcome" : rewardReady ? "too_reward_celebration" : (timed!.value.stamps > 0 ? "too_cookie_jar" : "too_welcome")
        return HStack(spacing: 12) {
            registeredArt(pose, width: 80, height: height)
            VStack(alignment: .leading, spacing: 5) {
                label(widgetCopy("B COOKIE LOYALTY CARD", "THẺ TÍCH TEM B COOKIE"))
                if usable, let timed {
                    let loyalty = timed.value
                    if rewardReady {
                        Text(widgetCopy("FREE FITBITES", "FITBITES MIỄN PHÍ"))
                            .font(.system(size: 19, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                        label(widgetCopy("READY TO CLAIM", "SẴN SÀNG ĐỂ NHẬN"))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(loyalty.stamps.formatted()).font(.system(size: 29, weight: .bold, design: .rounded))
                            Text("/ \(loyalty.target)").font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(widgetCopy("STAMPS", "TEM")).font(.system(size: 9, weight: .semibold, design: .rounded))
                        }.frame(height: 29, alignment: .leading)
                    }
                    HStack(spacing: 2) {
                        let count = rewardReady ? loyalty.displayedCardStamps : max(0, min(loyalty.target, loyalty.stamps))
                        ForEach(0..<min(12, max(1, loyalty.target)), id: \.self) { index in
                            Group {
                                if index < count { stampImage }
                                else { Image("BCookieStamp").resizable().renderingMode(.template).scaledToFit().foregroundStyle(ink.opacity(0.10)) }
                            }.frame(maxWidth: .infinity).frame(height: 22)
                        }
                    }.accessibilityHidden(true)
                    Text(timed.isStale(at: entry.date) ? updateHint(timed.fetchedAt) : "Too: '\(loyalty.tooComment)'")
                        .font(.system(size: 9, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.85)
                } else {
                    Text(widgetCopy("Open to update your card", "Mở để cập nhật thẻ của bạn"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: height).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private func reorderSection(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            Group {
                if let imageName = freshOrder?.imageName, let image = WidgetRasterImage.product(imageName, size: CGSize(width: 80, height: min(80, height)), fill: false) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "takeoutbag.and.cup.and.straw.fill").resizable().scaledToFit()
                        .foregroundStyle(honey).padding(17)
                }
            }.frame(width: 80, height: min(80, height)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                label(widgetCopy("ORDER AGAIN", "ĐẶT LẠI MÓN"))
                if let order = freshOrder {
                    Text(order.name).font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.85)
                    HStack {
                        Text(widgetCopy("View order", "Xem đơn hàng"))
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }.font(.system(size: 10, weight: .semibold, design: .rounded))
                } else {
                    Text(snapshot.orders?.isStale(at: entry.date) == true
                         ? widgetCopy("Refresh recent orders", "Cập nhật đơn gần đây")
                         : widgetCopy("Find your next favourite", "Tìm món yêu thích mới"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(2)
                    Text(widgetCopy("Open MyFitbites", "Mở MyFitbites")).font(.system(size: 10, design: .rounded))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: height).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    @ViewBuilder private var stampImage: some View {
        if #available(iOS 18.0, *) { Image("BCookieStamp").resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit() }
        else { Image("BCookieStamp").resizable().scaledToFit() }
    }
    private func registeredArt(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        let r: (CGSize, CGRect) = {
            switch name {
            case "today_tiel_audit": return (CGSize(width: 1145, height: 1374), CGRect(x: 182, y: 23, width: 859, height: 1317))
            case "too_cookie_jar": return (CGSize(width: 1202, height: 1308), CGRect(x: 219, y: 22, width: 781, height: 1258))
            case "too_reward_celebration": return (CGSize(width: 1202, height: 1309), CGRect(x: 150, y: 45, width: 961, height: 1214))
            default: return (CGSize(width: 1122, height: 1402), CGRect(x: 104, y: 46, width: 974, height: 1319))
            }
        }()
        let scale = min((width - 2) / r.1.width, (height - 2) / r.1.height)
        return artImage(name).frame(width: r.0.width * scale, height: r.0.height * scale)
            .offset(x: (r.0.width / 2 - r.1.midX) * scale, y: (r.0.height / 2 - r.1.midY) * scale)
            .frame(width: width, height: height).accessibilityHidden(true)
    }
    @ViewBuilder private func artImage(_ name: String) -> some View {
        if #available(iOS 18.0, *) { Image(name).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit() }
        else { Image(name).resizable().scaledToFit() }
    }
}


// Three small models share the approved white surface and compact branding.
enum FitbitesSmallModel: String, CaseIterable { case member, loyalty, reorder }

struct MyFitbitesSmallView: View {
    let entry: FitbitesEntry
    let model: FitbitesSmallModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var dark: Bool { entry.configuration.appearance == .espresso || (entry.configuration.appearance == .system && colorScheme == .dark) }
    private var ink: Color { renderingMode == .fullColor ? (dark ? Color(red: 1, green: 0.94, blue: 0.81) : Color(red: 0.24, green: 0.15, blue: 0.10)) : .primary }
    private let honey = Color(red: 0.91, green: 0.64, blue: 0.16)
    private var title: String {
        switch model {
        case .member: widgetCopy("LEVEL & XP", "CẤP ĐỘ & XP")
        case .loyalty: widgetCopy("LOYALTY CARD", "THẺ TÍCH ĐIỂM")
        case .reorder: widgetCopy("ORDER AGAIN", "ĐẶT LẠI MÓN")
        }
    }
    private var freshOrder: WidgetSnapshot.Reorder? {
        guard snapshot.status == .ready, let orders = snapshot.orders, !orders.isStale(at: entry.date) else { return nil }
        return orders.value.first
    }
    private var route: URL {
        switch model {
        case .member: WidgetRoute(topic: .today, itemID: "member", sessionID: snapshot.sessionID).url
        case .loyalty: WidgetRoute(topic: .stamps, sessionID: snapshot.sessionID).url
        case .reorder: WidgetRoute(topic: .reorder, itemID: freshOrder.map { String($0.id) }, sessionID: snapshot.sessionID).url
        }
    }
    var body: some View {
        GeometryReader { proxy in
            if model == .reorder, let order = freshOrder, let name = order.imageName,
               let photo = WidgetRasterImage.product(name, size: proxy.size, fill: true) {
                fullBleedOrder(order, photo: photo, size: proxy.size)
            } else {
            VStack(alignment: .leading, spacing: 4) {
                VStack(spacing: 2) {
                    Image("FitbitesLogo").resizable().interpolation(.high).scaledToFit().frame(width: 60, height: 15)
                        .background(dark ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                        .accessibilityHidden(true)
                    Text(title).font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(0.4)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }.frame(maxWidth: .infinity, alignment: .trailing).frame(height: 27)
                if snapshot.status != .ready {
                    unavailable(snapshot.status == .signedOut ? widgetCopy("Sign in to MyFitbites", "Đăng nhập MyFitbites") : widgetCopy("Open to update", "Mở để cập nhật"))
                } else {
                    switch model {
                    case .member: memberContent(height: max(45, proxy.size.height - 106))
                    case .loyalty: loyaltyContent(height: max(45, proxy.size.height - 99))
                    case .reorder: reorderContent(height: max(45, proxy.size.height - 99))
                    }
                }
            }.padding(12)
            }
        }
        .foregroundStyle(ink).fontDesign(.rounded)
        .containerBackground(for: .widget) { dark ? Color(red: 0.15, green: 0.10, blue: 0.08) : Color.white }
        .widgetURL(route).privacySensitive()
    }
    private func fullBleedOrder(_ order: WidgetSnapshot.Reorder, photo: UIImage, size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: photo).resizable().interpolation(.high).scaledToFill()
                .frame(width: size.width, height: size.height).clipped().accessibilityHidden(true)
            LinearGradient(stops: [.init(color: .black.opacity(0.60), location: 0),
                                   .init(color: .black.opacity(0.45), location: 0.20),
                                   .init(color: .clear, location: 0.42),
                                   .init(color: .black.opacity(0.12), location: 0.55),
                                   .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                photoBrand.frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 8)
                Text(order.name).font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(2).truncationMode(.tail)
                HStack {
                    Text(widgetCopy("ORDER AGAIN", "ĐẶT LẠI MÓN")).tracking(0.6)
                    Spacer(minLength: 3)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }.font(.system(size: 8.5, weight: .bold, design: .rounded))
            }.padding(12).foregroundStyle(.white)
        }.frame(width: size.width, height: size.height)
    }
    private var photoBrand: some View {
        ZStack {
            // The trademark "bites" keeps the exact colours from the approved logo.
            // Only "fit" receives the permitted white treatment over photography.
            if #available(iOS 18.0, *) {
                Image("FitbitesLogo").renderingMode(.original).resizable().interpolation(.high)
                    .widgetAccentedRenderingMode(.fullColor).scaledToFit()
            } else {
                Image("FitbitesLogo").renderingMode(.original).resizable().interpolation(.high).scaledToFit()
            }
            Image("FitbitesLogo").renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                .foregroundStyle(.white)
                .mask(alignment: .leading) {
                    // 188 lies in the transparent gap after "fit" in the 640-pixel source.
                    Rectangle().frame(width: 65 * 188 / 640)
                }
        }.frame(width: 65, height: 16)
            .shadow(color: .black.opacity(0.55), radius: 1, x: 0, y: 1)
            .accessibilityHidden(true)
    }
    @ViewBuilder private func memberContent(height: CGFloat) -> some View {
        if let member = snapshot.member, !member.isExpiredForToday(at: entry.date) {
            HStack(alignment: .center, spacing: 4) {
                SmallWidgetCharacter(name: "today_tiel_audit", width: 64, height: height + 28)
                    .offset(y: -14).frame(height: height)
                Spacer(minLength: 0)
                Text(member.value.level.formatted())
                    .font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65).widgetAccentable()
                    .accessibilityLabel(widgetCopy("Level ", "Cấp ") + member.value.level.formatted())
            }.frame(height: height)
            Text(member.value.tier).font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.8)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(honey.opacity(0.18))
                    Capsule().fill(honey).frame(width: proxy.size.width * member.value.progress)
                }
            }.frame(height: 5).accessibilityHidden(true)
            Text(member.isStale(at: entry.date) ? updated(member.fetchedAt)
                 : member.value.isMaximumLevel ? widgetCopy("Maximum level", "Cấp cao nhất")
                 : "\(member.value.levelXP.formatted()) / \(member.value.levelTarget.formatted()) XP")
                .font(.system(size: 8.5, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(member.isStale(at: entry.date)
                    ? "\(member.value.levelXP) / \(member.value.levelTarget) XP. " + updated(member.fetchedAt)
                    : member.value.isMaximumLevel ? widgetCopy("Maximum level", "Cấp cao nhất") : "\(member.value.levelXP) / \(member.value.levelTarget) XP")
        } else { unavailable(widgetCopy("Open to update your progress", "Mở để cập nhật tiến độ")) }
    }
    @ViewBuilder private func loyaltyContent(height: CGFloat) -> some View {
        if let timed = snapshot.loyalty, !timed.isExpiredForToday(at: entry.date) {
            let loyalty = timed.value
            let rewardReady = loyalty.rewardReady && !timed.isStale(at: entry.date)
            let pose = rewardReady ? "too_reward_celebration" : loyalty.stamps > 0 ? "too_cookie_jar" : "too_welcome"
            HStack(spacing: 5) {
                SmallWidgetCharacter(name: pose, width: 64, height: height + 24)
                    .offset(y: -12).frame(height: height)
                Spacer(minLength: 0)
                if rewardReady {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(widgetCopy("FREE", "MIỄN PHÍ"))
                        Text("FITBITES")
                    }.font(.system(size: 13, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(loyalty.stamps.formatted()).font(.system(size: 31, weight: .bold, design: .rounded))
                            Text("/\(loyalty.target)").font(.system(size: 13, weight: .bold, design: .rounded))
                        }.lineLimit(1).minimumScaleFactor(0.7)
                        Text(widgetCopy("STAMPS", "TEM")).font(.system(size: 8, weight: .semibold, design: .rounded))
                    }
                }
            }.frame(height: height)
            HStack(spacing: 2) {
                let count = rewardReady ? loyalty.displayedCardStamps : max(0, min(loyalty.target, loyalty.stamps))
                ForEach(0..<min(12, max(1, loyalty.target)), id: \.self) { index in
                    Group {
                        if index < count { cookie }
                        else { Image("BCookieStamp").resizable().renderingMode(.template).scaledToFit().foregroundStyle(ink.opacity(dark ? 0.22 : 0.10)) }
                    }.frame(maxWidth: .infinity).frame(height: 18)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(rewardReady ? widgetCopy("Completed card. Free Fitbites ready.", "Đủ tem. Có Fitbites miễn phí.") : widgetCopy("\(loyalty.stamps) of \(loyalty.target) B-cookie stamps", "\(loyalty.stamps) trên \(loyalty.target) tem B cookie"))
            Text(timed.isStale(at: entry.date) ? updated(timed.fetchedAt) : rewardReady ? widgetCopy("Tap to claim", "Chạm để nhận")
                 : widgetCopy("\(max(0, loyalty.target - loyalty.stamps)) to your free Fitbites", "Còn \(max(0, loyalty.target - loyalty.stamps)) tem đến quà"))
                .font(.system(size: 9, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
        } else { unavailable(widgetCopy("Open to update your card", "Mở để cập nhật thẻ")) }
    }
    @ViewBuilder private func reorderContent(height: CGFloat) -> some View {
        if let order = freshOrder {
            Group {
                if let name = order.imageName, let image = UIImage(named: name) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "takeoutbag.and.cup.and.straw.fill").resizable().scaledToFit().foregroundStyle(honey).padding(8)
                }
            }.frame(maxWidth: .infinity).frame(height: height).accessibilityHidden(true)
            Text(order.name).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).truncationMode(.tail)
            HStack {
                Text(widgetCopy("View order", "Xem đơn hàng"))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }.font(.system(size: 9, weight: .semibold, design: .rounded))
        } else {
            unavailable(snapshot.orders?.isStale(at: entry.date) == true
                ? widgetCopy("Refresh recent orders", "Cập nhật đơn gần đây")
                : widgetCopy("Find your next favourite", "Tìm món yêu thích mới"))
        }
    }
    private func updated(_ date: Date) -> String {
        widgetCopy("Updated ", "Cập nhật ") + date.formatted(date: .omitted, time: .shortened)
    }
    private func unavailable(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: model == .reorder ? "bag" : "arrow.clockwise").font(.system(size: 23, weight: .medium)).foregroundStyle(honey).accessibilityHidden(true)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(3).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    @ViewBuilder private var cookie: some View {
        if #available(iOS 18.0, *) { Image("BCookieStamp").resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit() }
        else { Image("BCookieStamp").resizable().scaledToFit() }
    }
}

private struct SmallWidgetCharacter: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        let bounds: CGRect = {
            switch name {
            case "today_tiel_audit": return CGRect(x: 182, y: 23, width: 859, height: 1317)
            case "too_cookie_jar": return CGRect(x: 219, y: 22, width: 781, height: 1258)
            case "too_reward_celebration": return CGRect(x: 150, y: 45, width: 961, height: 1214)
            default: return CGRect(x: 104, y: 46, width: 974, height: 1319)
            }
        }()
        let image = WidgetRasterImage.character(name, bounds: bounds, size: CGSize(width: width - 2, height: height - 2))
        return Group {
            if let image {
                if #available(iOS 18.0, *) {
                    Image(uiImage: image).resizable().interpolation(.high).widgetAccentedRenderingMode(.fullColor).scaledToFit()
                } else { Image(uiImage: image).resizable().interpolation(.high).scaledToFit() }
            }
        }.frame(width: width - 2, height: height - 2).frame(width: width, height: height).accessibilityHidden(true)
    }
}

/// Keep original bundled artwork, but archive only the pixels the widget actually displays.
/// WidgetKit rejects oversized source bitmaps even when SwiftUI scales them down visually.
private enum WidgetRasterImage {
    private static let cache = NSCache<NSString, UIImage>()
    static func character(_ name: String, bounds: CGRect, size: CGSize) -> UIImage? {
        let key = "character-\(name)-\(size.width)-\(size.height)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = UIImage(named: name), let bitmap = source.cgImage else { return nil }
        // These measured bounds remove only transparent canvas; the crest, props and feet stay intact.
        guard let crop = bitmap.cropping(to: bounds) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = false
        let output = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let rect = CGRect(x: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2,
                              width: bounds.width * scale, height: bounds.height * scale)
            UIImage(cgImage: crop).draw(in: rect)
        }
        cache.setObject(output, forKey: key)
        return output
    }
    static func product(_ name: String, size: CGSize, fill: Bool) -> UIImage? {
        let key = "product-\(name)-\(size.width)-\(size.height)-\(fill)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = UIImage(named: name), source.size.width > 0, source.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = fill
        let output = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            if fill { UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)) }
            let x = size.width / source.size.width, y = size.height / source.size.height
            let scale = fill ? max(x, y) : min(x, y)
            source.draw(in: CGRect(x: (size.width - source.size.width * scale) / 2,
                                  y: (size.height - source.size.height * scale) / 2,
                                  width: source.size.width * scale, height: source.size.height * scale))
        }
        cache.setObject(output, forKey: key)
        return output
    }
}
