import SwiftUI
import UIKit

struct RicoComicStoreCard: View {
    let item: RicoStoreItem
    let open: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var coverImage: UIImage?
    @State private var coverFailed = false
    @State private var coverRetry = 0

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFit()
                    } else if coverFailed {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(FBColors.cookieOrange)
                    } else {
                        ProgressView()
                    }
                }
                .accessibilityHidden(true)
                .frame(width: 96, height: 120)
                .background(FBColors.ivory)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.isOwned ? "MY COMICS" : "TOO & TIEL COMICS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FBColors.muted)
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(FBColors.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.shortDescription)
                        .font(.caption)
                        .foregroundStyle(FBColors.muted)
                    Text(item.isOwned ? "Read comic" : "Preview · \(item.coinPrice) Rico Coins")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FBColors.cookieOrange)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .task(id: "\(item.id)-\(coverRetry)") {
            coverImage = nil
            coverFailed = false
            guard let client = appState.customerAPIClient else {
                coverFailed = true
                return
            }
            do {
                let image = try await client.comicPage(id: item.id, page: 1)
                try Task.checkCancellation()
                coverImage = await image.byPreparingThumbnail(ofSize: CGSize(width: 288, height: 360)) ?? image
            } catch {
                if !Task.isCancelled { coverFailed = true }
            }
        }
        .accessibilityAction(named: "Reload cover") { coverRetry += 1 }

    }
}

struct RicoComicReader: View {
    let item: RicoStoreItem
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var comic: CustomerV2ComicPayload?
    @State private var errorMessage: String?
    @State private var selectedPage = 1
    @State private var confirmUnlock = false
    @State private var isLoading = false

    private var currentItem: RicoStoreItem {
        appState.rewardsRepository.rewards().ricoStoreItems.first { $0.id == item.id } ?? item
    }
    private var isPurchasing: Bool { appState.ricoPurchaseIDsInFlight.contains(item.id) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let comic, let client = appState.customerAPIClient {
                    TabView(selection: $selectedPage) {
                        ForEach(comic.pages) { page in
                            RicoComicPage(client: client, itemID: item.id, page: page)
                                .tag(page.number)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .background(Color.black)
                    HStack {
                        Text(comic.isOwned ? "\(selectedPage) / \(comic.pageCount)" : "Free preview · 1 / \(comic.pageCount)")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        if comic.isOwned {
                            Text("Swipe to read · Pinch to zoom").font(.caption)
                        }
                    }
                    .padding()
                    if !comic.isOwned {
                        Text(item.flavorText)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button {
                            confirmUnlock = true
                        } label: {
                            Text(isPurchasing ? "Unlocking…" : "Unlock · \(currentItem.coinPrice) Rico Coins")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FBColors.cookieOrange)
                        .disabled(isPurchasing || !currentItem.isAvailable || !appState.canAttemptRicoStorePurchase)
                        .padding()
                        if !currentItem.isAvailable, let reason = currentItem.lockReason {
                            Text(reason).font(.caption).padding(.bottom, 8)
                        }
                    }
                } else if isLoading {
                    Spacer()
                    ProgressView("Opening comic…")
                    Spacer()
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).multilineTextAlignment(.center).padding()
                    Button("Try again") { Task { await load() } }.padding(.bottom)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Unlock for \(currentItem.coinPrice) Rico Coins?", isPresented: $confirmUnlock, titleVisibility: .visible) {
                Button("Unlock for \(currentItem.coinPrice) Rico Coins") {
                    Task {
                        await appState.purchaseRicoStoreItem(currentItem)
                        let purchaseError = appState.ricoStoreErrorMessage
                        await load()
                        if comic?.isOwned != true { errorMessage = purchaseError ?? "The unlock could not be confirmed. Please try again." }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Unlock all \(comic?.pageCount ?? 0) pages once and read them anytime. Your balance: \(appState.rewardsRepository.rewards().ricoWallet.balance) Rico Coins.")
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let client = appState.customerAPIClient else {
            errorMessage = "Sign in to open this comic."
            return
        }
        do {
            let result = try await client.comic(id: item.id)
            guard !result.pages.isEmpty else { throw URLError(.badServerResponse) }
            comic = result
            if !result.pages.contains(where: { $0.number == selectedPage }) { selectedPage = 1 }
        } catch {
            errorMessage = "Couldn't load the comic. Check your connection and try again."
        }
    }
}

private struct RicoComicPage: View {
    let client: CustomerV2APIClient
    let itemID: String
    let page: CustomerV2ComicPayload.Page
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        ZStack {
            Color.black
            if let image {
                RicoComicZoomView(image: image)
                    .accessibilityLabel(page.caption)
            } else if failed {
                VStack(spacing: 12) {
                    Text("Couldn't load page \(page.number).")
                    Button("Retry") { retry += 1 }
                }.foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: retry) {
            guard image == nil else { return }
            failed = false
            do {
                image = try await client.comicPage(id: itemID, page: page.number)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct RicoComicZoomView: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ComicScrollView { ComicScrollView() }
    func updateUIView(_ view: ComicScrollView, context: Context) {
        if view.artwork.image !== image {
            view.setZoomScale(1, animated: false)
            view.artwork.image = image
            view.setNeedsLayout()
        }
    }
}

private final class ComicScrollView: UIScrollView, UIScrollViewDelegate {
    let artwork = UIImageView()
    private var previousSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        artwork.contentMode = .scaleAspectFit
        addSubview(artwork)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != bounds.size {
            previousSize = bounds.size
            setZoomScale(1, animated: false)
            artwork.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { artwork }
    @objc private func toggleZoom() {
        setZoomScale(zoomScale > 1 ? 1 : 2, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}
