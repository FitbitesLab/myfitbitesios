import SwiftUI

struct MyCollectiblesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CustomerV2RicoCollectionPayload.Item] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedComic: RicoStoreItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { dismiss() } label: {
                    Text("BACK")
                        .font(.custom("AvenirNext-DemiBold", size: 10))
                        .tracking(1.5)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                Text("MY COLLECTIBLES")
                    .font(.custom("AvenirNext-DemiBold", size: 18))
                    .tracking(1.5)

                if isLoading && items.isEmpty {
                    ProgressView("Loading collectibles…")
                        .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                        Button("Try again") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity)
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 32))
                            .foregroundStyle(FBColors.cookieOrange)
                        Text("Your collection starts here")
                            .font(.custom("AvenirNext-DemiBold", size: 16))
                        Text("Items you unlock in the Rico Store will appear here.")
                            .foregroundStyle(FBColors.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        if item.itemType == "too_tiel_episode", let id = item.itemId {
                            let comic = comicItem(item, id: id)
                            RicoComicStoreCard(item: comic) { selectedComic = comic }
                        } else {
                            HStack(spacing: 16) {
                                AsyncImage(url: item.imageRef.flatMap(URL.init(string:))) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundStyle(FBColors.cookieOrange)
                                }
                                .frame(width: 72, height: 88)
                                Text(item.name ?? "Collectible")
                                    .font(.custom("AvenirNext-DemiBold", size: 16))
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .background(FBColors.ivory, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            .padding(.horizontal, FBSpacing.md)
            .padding(.bottom, FBSpacing.xl)
        }
        .font(.custom("AvenirNext-Regular", size: 14))
        .foregroundStyle(FBColors.charcoal)
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedComic) { RicoComicReader(item: $0) }
    }

    private func comicItem(_ item: CustomerV2RicoCollectionPayload.Item, id: String) -> RicoStoreItem {
        RicoStoreItem(id: id, name: item.name ?? "Too & Tiel comic",
                      shortDescription: "", flavorText: "", imageRef: item.imageRef,
                      coinPrice: 0, itemType: "too_tiel_episode", remainingStock: nil,
                      isOwned: true, isAvailable: true, lockReason: nil, isLimited: false)
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let client = appState.customerAPIClient else {
            errorMessage = "Sign in to view your collectibles."
            return
        }
        do {
            let collection = try await client.ricoCollection()
            try Task.checkCancellation()
            items = collection.items ?? []
        } catch is CancellationError {
        } catch {
            errorMessage = "Your collectibles couldn’t load. Please try again."
        }
    }
}
