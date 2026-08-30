import SwiftUI
import UIKit

enum FBColors {
    static let ivory = Color(red: 0.961, green: 0.949, blue: 0.922)
    static let surface = Color(red: 0.988, green: 0.988, blue: 0.980)
    static let card = Color(red: 0.961, green: 0.949, blue: 0.922)
    static let charcoal = Color(red: 0.075, green: 0.071, blue: 0.065)
    static let muted = Color(red: 0.420, green: 0.380, blue: 0.330)
    static let line = Color(red: 0.910, green: 0.886, blue: 0.843)
    static let cookieOrange = Color(red: 0.796, green: 0.580, blue: 0.416)
    static let caramel = Color(red: 0.760, green: 0.360, blue: 0.060)
    static let tielYellow = Color(red: 0.950, green: 0.720, blue: 0.150)
}

enum FBSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 30
}

enum FBCorner {
    static let compact: CGFloat = 8
    static let card: CGFloat = 18
    static let hero: CGFloat = 28
}

extension Font {
    private static func avenirNextName(for weight: Weight) -> String {
        switch weight {
        case .black, .heavy, .bold, .semibold:
            "AvenirNext-DemiBold"
        case .medium:
            "AvenirNext-Medium"
        default:
            "AvenirNext-Regular"
        }
    }

    static func fbTitle(_ weight: Weight = .bold) -> Font {
        .custom(avenirNextName(for: weight), size: 34)
    }

    static func fbHeadline(_ weight: Weight = .bold) -> Font {
        .custom(avenirNextName(for: weight), size: 17)
    }

    static func fbBody(_ weight: Weight = .regular) -> Font {
        .custom(avenirNextName(for: weight), size: 17)
    }

    static func fbCaption(_ weight: Weight = .regular) -> Font {
        .custom(avenirNextName(for: weight), size: 12)
    }

}

struct FBPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title.uppercased())
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, FBSpacing.lg)
            .frame(height: 58)
            .background(FBColors.cookieOrange, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .shadow(color: FBColors.cookieOrange.opacity(0.24), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct FBStatCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = FBColors.cookieOrange

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.fbHeadline(.bold))
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.fbCaption())
                    .foregroundStyle(FBColors.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65), lineWidth: 1))
    }
}

struct FBXPProgress: View {
    let level: Int
    let xp: Int
    let xpToNext: Int
    let targetXP: Int
    var headline: String?
    var avatar: LocalAvatar = .default
    var maxLevel: Int = 99

    private var displayMaxLevel: Int {
        MyFitbitesLevelDisplay.bandMax(for: level, absoluteMax: maxLevel)
    }

    private var progress: Double {
        let earned = max(0, targetXP - xpToNext)
        return min(1, max(0, Double(earned) / Double(max(1, targetXP))))
    }

    private var displayHeadline: String {
        let trimmedHeadline = headline?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedHeadline, !trimmedHeadline.isEmpty else {
            return "\(xp.formatted()) XP"
        }

        return trimmedHeadline
    }

    var body: some View {
        HStack(spacing: FBSpacing.md) {
            FBAvatarView(avatar: avatar, size: 64)

            VStack(alignment: .leading, spacing: 8) {
                Text(displayHeadline)
                    .font(.custom("AvenirNext-Regular", size: 22))
                    .tracking(0.8)
                    .foregroundStyle(FBColors.charcoal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressView(value: progress)
                    .tint(FBColors.cookieOrange)
                    .accessibilityLabel("XP progress")
                HStack {
                    Text("LEVEL \(level)/\(displayMaxLevel)")
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(targetXP.formatted()) XP")
                }
                .font(.fbCaption())
                .foregroundStyle(FBColors.muted)
            }
        }
        .padding(FBSpacing.md)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65), lineWidth: 1))
    }
}

enum MyFitbitesLevelDisplay {
    static func bandMax(for level: Int, absoluteMax: Int = 99) -> Int {
        let normalizedLevel = max(1, level)
        let bandMax: Int

        switch normalizedLevel {
        case 1...24:
            bandMax = 24
        case 25...49:
            bandMax = 49
        case 50...73:
            bandMax = 73
        default:
            bandMax = 99
        }

        return min(bandMax, absoluteMax)
    }
}

struct FBAvatarView: View {
    let avatar: LocalAvatar
    var size: CGFloat = 64

    private var preset: LocalAvatarPreset {
        LocalAvatarPreset.preset(for: avatar.presetID)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            avatarContent
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 2))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 7)
        .accessibilityLabel("\(preset.name) avatar")
    }

    @ViewBuilder
    private var avatarContent: some View {
        if
            let customPhotoData = avatar.customPhotoData,
            let image = UIImage(data: customPhotoData)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else if let imageName = preset.imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else if let symbolName = preset.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Text(preset.initials)
                .font(.custom("AvenirNext-DemiBold", size: size * 0.28))
                .foregroundStyle(.white)
        }
    }
}

struct LoyaltyStampGrid: View {
    let completed: Int
    let total: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(1...total, id: \.self) { index in
                StampView(index: index, isComplete: index <= completed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) loyalty stamps complete")
    }
}

private struct StampView: View {
    let index: Int
    let isComplete: Bool

    var body: some View {
        ZStack {
            if isComplete {
                Image("BCookieStamp")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 48)
            } else {
                Image("BCookieStamp")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(FBColors.line.opacity(0.72))
                    .frame(width: 44, height: 48)
                    .opacity(0.58)
            }
        }
        .frame(width: 52, height: 52)
    }
}
