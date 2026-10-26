import SwiftUI

struct RewardsPageHero: View {
    let artwork: String
    let title: String

    var body: some View {
        Color.clear
            .aspectRatio(1.6, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    Image(artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(.custom("AvenirNext-DemiBold", size: 28))
                    .foregroundStyle(.white)
                    .padding(22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}

struct RewardsPageBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FBColors.charcoal)
                .frame(width: 32, height: 32)
                .background(FBColors.surface, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Rewards")
    }
}
