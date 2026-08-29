import MapKit
import SwiftUI

struct StoreView: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var categorySelectionNamespace
    @State private var fulfillment: Fulfillment = .pickup
    @State private var selectedCategoryID = "oats"
    @State private var selectedProduct: StoreProduct?
    @State private var isCartOpen = false

    private var catalog: StoreCatalog { appState.catalogRepository.catalog() }

    private var visibleProducts: [StoreProduct] {
        catalog.products.filter { $0.categoryID == selectedCategoryID }
    }

    private func productCount(for category: StoreCategory) -> Int {
        return catalog.products.filter { $0.categoryID == category.id }.count
    }

    private let productColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var cartSheetHeight: CGFloat {
        let cartRows = CGFloat(min(max(appState.cart.lines.count, 1), 3))
        let checkoutPanelHeight: CGFloat = fulfillment == .delivery ? 430 : 250
        let desiredHeight = 118 + (cartRows * 116) + checkoutPanelHeight

        return min(max(desiredHeight, fulfillment == .delivery ? 640 : 500), 760)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FBSpacing.lg) {
                    storeHeader
                    familyRail
                        .zIndex(2)

                    LazyVGrid(columns: productColumns, spacing: 14) {
                        ForEach(visibleProducts) { product in
                            ProductGridCard(product: product, quantity: quantityFor(product)) {
                                selectedProduct = product
                            } onQuickAdd: {
                                withAnimation(.snappy) {
                                    appState.cart.add(product)
                                }
                            }
                        }
                    }
                    .id(selectedCategoryID)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: selectedCategoryID)
                }
                .padding(.horizontal, FBSpacing.md)
                .padding(.top, FBSpacing.sm)
                .padding(.bottom, appState.cart.itemCount > 0 ? 118 : 104)
            }

            if appState.cart.itemCount > 0 {
                CartBar(count: appState.cart.itemCount, subtotal: appState.cart.subtotalVND) {
                    isCartOpen = true
                }
                .padding(.horizontal, FBSpacing.md)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedProduct) { product in
            ProductDetailView(product: product)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isCartOpen) {
            CartSummarySheet(fulfillment: fulfillment)
                .presentationDetents([.height(cartSheetHeight)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(FBColors.surface)
        }
        .onAppear {
            openPendingProductIfNeeded()
            openCartIfRequested()
        }
        .onChange(of: appState.pendingStoreProductID) { _, _ in
            openPendingProductIfNeeded()
        }
        .onChange(of: appState.shouldOpenCartOnOrderTab) { _, _ in
            openCartIfRequested()
        }
    }

    private func openPendingProductIfNeeded() {
        guard let productID = appState.pendingStoreProductID else { return }
        selectedProduct = catalog.products.first { $0.id == productID }
        appState.pendingStoreProductID = nil
    }

    private func openCartIfRequested() {
        guard appState.shouldOpenCartOnOrderTab else { return }
        appState.shouldOpenCartOnOrderTab = false
        guard appState.cart.itemCount > 0 else { return }
        DispatchQueue.main.async {
            isCartOpen = true
        }
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: FBSpacing.md) {
            ZStack {
                Image("MyStoreLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                    .accessibilityLabel("myStore")

                Button {} label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FBColors.charcoal)
                        .frame(width: 46, height: 46)
                        .background(FBColors.surface, in: Circle())
                        .overlay(Circle().stroke(FBColors.line.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search menu")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)

            FulfillmentSwitch(selection: $fulfillment)
        }
    }

    private var familyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(catalog.categories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedCategoryID = category.id
                        }
                    } label: {
                        let isSelected = selectedCategoryID == category.id
                        HStack(spacing: 7) {
                            Text(categoryDisplayName(category))
                                .font(.custom("AvenirNext-DemiBold", size: 11))
                                .tracking(1.15)
                                .lineLimit(1)
                            Text("\(productCount(for: category))")
                                .font(.custom("AvenirNext-Regular", size: 10))
                                .monospacedDigit()
                                .opacity(isSelected ? 0.72 : 0.50)
                        }
                        .textCase(.uppercase)
                        .foregroundStyle(isSelected ? .white : FBColors.charcoal)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(FBColors.charcoal)
                                    .matchedGeometryEffect(id: "categorySelection", in: categorySelectionNamespace)
                            } else {
                                Capsule()
                                    .fill(Color.white)
                            }
                        }
                        .overlay(Capsule().stroke(isSelected ? Color.clear : FBColors.line.opacity(0.72)))
                        .shadow(color: isSelected ? FBColors.charcoal.opacity(0.16) : .clear, radius: 9, y: 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(category.name)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryDisplayName(_ category: StoreCategory) -> String {
        switch category.id {
        case "oats": "Oats"
        case "yogurt": "Yogurt"
        case "smoothies": "Smoothies"
        case "desserts": "Desserts"
        default: category.name
        }
    }

    private func quantityFor(_ product: StoreProduct) -> Int {
        appState.cart.lines
            .filter { $0.product.inventoryItemID == product.inventoryItemID }
            .reduce(0) { $0 + $1.quantity }
    }
}

private struct FulfillmentSwitch: View {
    @Binding var selection: Fulfillment
    @Namespace private var fulfillmentSelectionNamespace

    var body: some View {
        HStack(spacing: 8) {
            FulfillmentButton(
                title: "pick up",
                symbol: "bag",
                isSelected: selection == .pickup,
                namespace: fulfillmentSelectionNamespace
            ) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    selection = .pickup
                }
            }

            FulfillmentButton(
                title: "delivery",
                symbol: "box.truck",
                isSelected: selection == .delivery,
                namespace: fulfillmentSelectionNamespace
            ) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    selection = .delivery
                }
            }
        }
        .padding(6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fulfillment method")
    }
}

private struct FulfillmentButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .tracking(0.85)
            }
            .foregroundStyle(isSelected ? .white : FBColors.charcoal)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FBColors.cookieOrange)
                        .matchedGeometryEffect(id: "fulfillmentSelection", in: namespace)
                }
            }
            .shadow(color: isSelected ? FBColors.cookieOrange.opacity(0.16) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum Fulfillment: String {
    case pickup
    case delivery

    var label: String {
        switch self {
        case .pickup: "Pickup"
        case .delivery: "Delivery"
        }
    }

    var feeVND: Int {
        switch self {
        case .pickup: 0
        case .delivery: 15_000
        }
    }
}

struct ProductImageTile: View {
    let imageName: String
    var imageURL: URL? = nil
    @State private var remoteImage: UIImage?
    @State private var remoteImageURL: URL?

    var body: some View {
        if let imageURL {
            remoteImageView(for: imageURL)
        } else {
            fallbackImage
        }
    }

    @ViewBuilder
    private func remoteImageView(for imageURL: URL) -> some View {
        if remoteImageURL == imageURL, let remoteImage {
            Image(uiImage: remoteImage)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            remoteImagePlaceholder
                .task(id: imageURL) {
                    remoteImageURL = imageURL
                    remoteImage = StoreImagePreloader.cachedImage(for: imageURL)
                    if remoteImage == nil {
                        remoteImage = await StoreImagePreloader.image(for: imageURL)
                    }
                }
        }
    }

    private var remoteImagePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FBColors.surface,
                    Color.white,
                    FBColors.line.opacity(0.42)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image("FitbitesLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 82)
                .opacity(0.18)
        }
        .accessibilityHidden(true)
    }

    private var fallbackImage: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .accessibilityHidden(true)
    }
}

private struct ProductGridCard: View {
    let product: StoreProduct
    let quantity: Int
    let onOpen: () -> Void
    let onQuickAdd: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        ProductImageTile(imageName: product.imageName, imageURL: product.imageURL)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.0), .black.opacity(0.62)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name)
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)

                        Text(product.priceVND.vndText)
                            .font(.custom("AvenirNext-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))
                .contentShape(RoundedRectangle(cornerRadius: FBCorner.card))
                .onTapGesture {
                    onOpen()
                }
                .onLongPressGesture(minimumDuration: 0.36) {
                    onOpen()
                }
                .accessibilityLabel("Open \(product.name)")

            if quantity > 0 {
                Text("\(quantity)")
                    .font(.fbCaption(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(FBColors.charcoal, in: Circle())
                    .offset(x: -6, y: 42)
                    .accessibilityLabel("\(quantity) in cart")
            }

            Button(action: onQuickAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.62), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(9)
            .accessibilityLabel("Add \(product.name) to cart")
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }
}

private struct ProductDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let product: StoreProduct

    @State private var quantity = 1
    @State private var selectedToppings: Set<StoreTopping> = []
    @State private var showsHeroDescription = false

    private var toppingGroups: [(String, [StoreTopping])] {
        let order = ["Greek Yogurt", "Extra Fruits", "Crunch", "Nut Butter", "Extras"]
        return Dictionary(grouping: product.toppings, by: \.category)
            .sorted { first, second in
                (order.firstIndex(of: first.key) ?? 999) < (order.firstIndex(of: second.key) ?? 999)
            }
    }

    private var unitTotal: Int {
        product.priceVND + selectedToppings.reduce(0) { $0 + $1.priceVND }
    }

    private var itemTotal: Int {
        unitTotal * quantity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FBSpacing.lg) {
                productHero

                NutritionGrid(product: product)

                if product.toppings.isEmpty {
                    Text("No toppings for this product yet.")
                        .font(.fbBody(.semibold))
                        .foregroundStyle(FBColors.muted)
                        .padding(FBSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
                } else {
                    toppingsSection
                }

                detailAction
            }
            .padding(FBSpacing.md)
            .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private var productHero: some View {
        ZStack(alignment: .bottom) {
            ProductImageTile(imageName: product.imageName, imageURL: product.imageURL)
                .frame(height: 318)
                .clipped()
                .transaction { transaction in
                    transaction.animation = nil
                }

            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            ZStack {
                if showsHeroDescription {
                    Text(product.description)
                        .font(.custom("AvenirNext-Regular", size: 14))
                        .tracking(1.05)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 42)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    Text(product.name)
                        .font(.custom("AvenirNext-DemiBold", size: 24))
                        .tracking(1.35)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 46)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showsHeroDescription)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FBSpacing.md)
            .padding(.bottom, FBSpacing.md)

            Button {
                showsHeroDescription.toggle()
            } label: {
                Image(systemName: showsHeroDescription ? "arrow.left" : "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(FBSpacing.md)
            .accessibilityLabel(showsHeroDescription ? "Show product name" : "Show product description")
        }
        .frame(height: 318)
        .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))
        .accessibilityLabel(showsHeroDescription ? product.description : product.name)
    }

    private var toppingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Toppings")
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .tracking(1.7)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.charcoal)

            VStack(spacing: 0) {
                ForEach(Array(toppingGroups.enumerated()), id: \.element.0) { groupIndex, group in
                    if groupIndex > 0 {
                        Divider()
                            .background(FBColors.line.opacity(0.75))
                    }

                    Text(group.0)
                        .font(.custom("AvenirNext-DemiBold", size: 10))
                        .tracking(1.55)
                        .textCase(.uppercase)
                        .foregroundStyle(FBColors.cookieOrange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, groupIndex == 0 ? 14 : 16)
                        .padding(.bottom, 6)

                    ForEach(Array(group.1.enumerated()), id: \.element.id) { index, topping in
                        ToppingRow(
                            topping: topping,
                            isSelected: selectedToppings.contains(topping)
                        ) {
                            if selectedToppings.contains(topping) {
                                selectedToppings.remove(topping)
                            } else {
                                selectedToppings.insert(topping)
                            }
                        }

                        if index < group.1.count - 1 {
                            Divider()
                                .background(FBColors.line.opacity(0.65))
                                .padding(.leading, 14)
                        }
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.62)))
        }
    }

    private var detailAction: some View {
        HStack(spacing: FBSpacing.md) {
            StepperControls(
                quantity: quantity,
                onDecrease: { quantity = max(1, quantity - 1) },
                onIncrease: { quantity = min(20, quantity + 1) }
            )
            .padding(.horizontal, 10)
            .frame(height: 56)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))

            Button {
                withAnimation(.snappy) {
                    appState.cart.add(product, toppings: Array(selectedToppings), quantity: quantity)
                }
                dismiss()
            } label: {
                HStack {
                    Text("Add")
                    Spacer()
                    Text(itemTotal.vndText)
                }
                .font(.fbHeadline(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, FBSpacing.md)
                .frame(height: 56)
                .background(FBColors.cookieOrange, in: RoundedRectangle(cornerRadius: FBCorner.card))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(quantity) \(product.name) for \(itemTotal.vndText)")
        }
    }
}

private struct NutritionGrid: View {
    let product: StoreProduct

    var body: some View {
        HStack(spacing: 0) {
            NutritionColumn(value: product.calories, label: "Calories", symbol: "flame")
            NutritionDivider()
            NutritionColumn(value: product.protein, label: "Protein", symbol: "figure.strengthtraining.traditional")
            NutritionDivider()
            NutritionColumn(value: product.sugar, label: "Sugar", symbol: "cube")
        }
        .frame(height: 86)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.62)))
    }
}

private struct NutritionColumn: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FBColors.cookieOrange)
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 17))
                .foregroundStyle(FBColors.charcoal)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NutritionDivider: View {
    var body: some View {
        Rectangle()
            .fill(FBColors.line.opacity(0.72))
            .frame(width: 1, height: 50)
    }
}

private struct ToppingRow: View {
    let topping: StoreTopping
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(topping.name)
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .tracking(1.05)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(FBColors.charcoal)
                Spacer()
                Text("+ \(topping.priceVND.vndText)")
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .tracking(0.55)
                    .foregroundStyle(FBColors.muted)
                Image(systemName: isSelected ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : FBColors.cookieOrange)
                    .frame(width: 26, height: 26)
                    .background(isSelected ? FBColors.cookieOrange : Color.clear, in: Circle())
                    .overlay(Circle().stroke(FBColors.cookieOrange.opacity(isSelected ? 0 : 0.6), lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(isSelected ? FBColors.surface.opacity(0.72) : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isSelected ? "Remove" : "Add") \(topping.name), \(topping.priceVND.vndText)")
    }
}

private struct CartBar: View {
    let count: Int
    let subtotal: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bag")
                    .font(.system(size: 20, weight: .semibold))
                Text("View cart")
                    .font(.fbHeadline(.semibold))
                Text("\(count)")
                    .font(.fbCaption(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(FBColors.cookieOrange, in: Circle())
                Spacer()
                Text(subtotal.vndText)
                    .font(.fbBody(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(FBColors.charcoal, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View cart, \(count) items, subtotal \(subtotal.vndText)")
    }
}

private struct CartSummarySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let fulfillment: Fulfillment
    @State private var isAddressFlowPresented = false

    private var total: Int {
        appState.cart.subtotalVND + deliveryFeeVND
    }

    private var confirmedAddresses: [SavedAddress] {
        appState.savedAddresses.filter(\.isConfirmedForDelivery)
    }

    private var selectedConfirmedAddress: SavedAddress? {
        appState.savedAddresses.first { $0.id == appState.selectedAddressID && $0.isConfirmedForDelivery }
    }

    private var deliveryFeeVND: Int {
        fulfillment == .delivery ? selectedConfirmedAddress?.lastQuotedDeliveryFeeVND ?? 0 : 0
    }

    private var canSubmit: Bool {
        !appState.isCheckoutSubmitting
            && !appState.cart.lines.isEmpty
            && (fulfillment == .pickup || selectedConfirmedAddress != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.custom("AvenirNext-DemiBold", size: 16))
                    .foregroundStyle(FBColors.cookieOrange)
                    .frame(height: 32)
            }
            .padding(.horizontal, FBSpacing.md)
            .padding(.top, 24)
            .padding(.bottom, 14)

            if appState.cart.lines.isEmpty {
                emptyCart
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.cart.lines.enumerated()), id: \.element.id) { index, line in
                            CartLineRow(
                                line: line,
                                showsDivider: index < appState.cart.lines.count - 1
                            )
                        }
                    }
                    .padding(.horizontal, FBSpacing.md)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollIndicators(.hidden)

                quotePanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FBColors.surface.ignoresSafeArea())
    }

    private var emptyCart: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FBColors.cookieOrange)
            Text("Your cart is empty")
                .font(.fbHeadline(.bold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var quotePanel: some View {
        VStack(spacing: 12) {
            QuoteRow(label: "Subtotal", value: appState.cart.subtotalVND.vndText)
            QuoteRow(label: fulfillment.label, value: deliveryFeeVND == 0 ? "Free" : deliveryFeeVND.vndText)
            Divider()
            QuoteRow(label: "Total", value: total.vndText, isStrong: true)

            if fulfillment == .delivery {
                deliveryAddressPicker
            }

            if let order = appState.lastSubmittedOrder {
                checkoutNotice(
                    title: "Order sent",
                    message: "\(fulfillment.label) order #\(order.id) is now in the Fitbites online queue."
                )
            }

            if let message = appState.checkoutErrorMessage {
                checkoutNotice(title: "Checkout failed", message: message)
            }

            #if DEBUG
            if fulfillment == .delivery {
                debugVnpaySandboxPanel
            }
            #endif

            FBPrimaryButton(
                title: appState.isCheckoutSubmitting ? "Sending order" : fulfillment == .delivery ? "Place delivery order" : "Place pickup order",
                systemImage: appState.isCheckoutSubmitting ? "hourglass" : "bag.badge.plus"
            ) {
                Task {
                    if fulfillment == .delivery {
                        await appState.submitDeliveryCheckout()
                    } else {
                        await appState.submitPickupCheckout()
                    }
                }
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.55)
        }
        .padding(FBSpacing.md)
        .padding(.bottom, 10)
        .background(FBColors.surface)
        .sheet(isPresented: $isAddressFlowPresented) {
            DeliveryAddressFlowView()
                .environmentObject(appState)
        }
        #if DEBUG
        .sheet(item: $appState.debugVnpayPaymentSession, onDismiss: {
            Task { await appState.refreshDebugVnpayPaymentStatus() }
        }) { session in
            DebugVnpaySandboxBrowser(url: session.url) {
                Task { await appState.refreshDebugVnpayPaymentStatus() }
            }
        }
        #endif
    }

    #if DEBUG
    private var debugVnpaySandboxPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INTERNAL VNPAY SANDBOX")
                        .font(.custom("AvenirNext-DemiBold", size: 11))
                        .tracking(1.2)
                    Text(appState.debugVnpayMessage ?? "Hidden debug payment lifecycle test.")
                        .font(.custom("AvenirNext-Regular", size: 12))
                        .foregroundStyle(FBColors.muted)
                }
                Spacer()
                Button {
                    Task { await appState.refreshDebugVnpayPaymentStatus() }
                } label: {
                    Image(systemName: appState.isDebugVnpayStatusRefreshing ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(appState.isDebugVnpayStatusRefreshing)
            }

            if let status = appState.debugVnpayPaymentStatus {
                HStack(spacing: 8) {
                    Text(status.paymentAttempt.status.uppercased())
                    Text(status.paymentAttempt.amount.value.vndText)
                    Text(status.pendingOrder.paymentStatus.uppercased())
                }
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .foregroundStyle(FBColors.charcoal.opacity(0.72))
            }

            FBPrimaryButton(
                title: appState.isDebugVnpaySubmitting ? "Starting sandbox" : "Pay with VNPAY sandbox",
                systemImage: appState.isDebugVnpaySubmitting ? "hourglass" : "creditcard"
            ) {
                Task { await appState.submitDebugVnpaySandboxDeliveryCheckout() }
            }
            .disabled(!canSubmit || appState.isDebugVnpaySubmitting)
            .opacity((canSubmit && !appState.isDebugVnpaySubmitting) ? 1 : 0.55)
        }
        .padding(14)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.purple.opacity(0.16), lineWidth: 1)
        )
    }
    #endif

    private func checkoutNotice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .tracking(0.7)
                .foregroundStyle(FBColors.charcoal)
            Text(message)
                .font(.custom("AvenirNext-Regular", size: 12))
                .tracking(0.25)
                .foregroundStyle(FBColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.compact))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.58)))
    }

    private var deliveryAddressPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Delivery address")
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .tracking(1.45)
                    .textCase(.uppercase)
                    .foregroundStyle(FBColors.charcoal)
                Spacer()
                Button("Add") {
                    isAddressFlowPresented = true
                }
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(FBColors.cookieOrange)
            }

            if confirmedAddresses.isEmpty {
                checkoutNotice(
                    title: "Confirm your delivery address",
                    message: "Add a map pin with Apple Maps or current location before delivery."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(confirmedAddresses) { address in
                        CartAddressChip(
                            address: address,
                            isSelected: address.id == appState.selectedAddressID
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                appState.selectSavedAddress(address)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.card))
        .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.58)))
    }
}

private struct CartAddressChip: View {
    let address: SavedAddress
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(address.label)
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .tracking(0.25)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if isSelected {
                    Text("Selected")
                        .font(.custom("AvenirNext-DemiBold", size: 10))
                        .tracking(0.65)
                        .textCase(.uppercase)
                }
            }
            .foregroundStyle(isSelected ? FBColors.cookieOrange : FBColors.charcoal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().overlay(FBColors.line.opacity(0.46))
        }
        .accessibilityLabel("Use \(address.label) delivery address")
    }
}

private struct DeliveryAddressFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationService = DeliveryLocationService()
    @State private var query = ""
    @State private var searchResults: [DeliveryPlaceSearchResult] = []
    @State private var selectedDraft: DeliveryAddressDraft?
    @State private var isSearching = false
    @State private var isLocating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let selectedDraft {
                    DeliveryPinConfirmationView(draft: selectedDraft) { address in
                        appState.saveConfirmedDeliveryAddress(address)
                        dismiss()
                    } onBack: {
                        self.selectedDraft = nil
                    }
                    .environmentObject(appState)
                } else {
                    findLocationView
                }
            }
            .background(Color.white.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(FBColors.cookieOrange)
                }
            }
        }
    }

    private var findLocationView: some View {
        VStack(alignment: .leading, spacing: FBSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delivery Address")
                    .font(.custom("AvenirNext-DemiBold", size: 24))
                    .tracking(0.4)
                    .foregroundStyle(FBColors.charcoal)
                Text("Search a building, condo, office or street address.")
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .tracking(0.35)
                    .foregroundStyle(FBColors.muted)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FBColors.muted)
                TextField("Gateway Thao Dien, BIS, Masteri...", text: $query)
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { search() }
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))

            Button {
                useCurrentLocation()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                    Text(isLocating ? "Finding you..." : "Use Current Location")
                    Spacer()
                    if isLocating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.custom("AvenirNext-DemiBold", size: 14))
                .foregroundStyle(FBColors.charcoal)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: FBCorner.card))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.65)))
            }
            .buttonStyle(.plain)

            if let errorMessage {
                Text(errorMessage)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .foregroundStyle(.red.opacity(0.82))
            }

            List(searchResults) { result in
                Button {
                    selectedDraft = DeliveryAddressDraft(
                        label: result.title,
                        title: result.title,
                        formattedAddress: result.savedAddressDetail,
                        latitude: result.latitude,
                        longitude: result.longitude,
                        coordinateSource: .appleMaps,
                        accuracy: nil
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                            .foregroundStyle(FBColors.charcoal)
                        Text(result.savedAddressDetail)
                            .font(.custom("AvenirNext-Regular", size: 12))
                            .foregroundStyle(FBColors.muted)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding(FBSpacing.md)
        .onChange(of: query) { _, newValue in
            guard newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
                searchResults = []
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard newValue == query else { return }
                await runSearch()
            }
        }
    }

    private func search() {
        Task { await runSearch() }
    }

    private func runSearch() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            searchResults = try await locationService.searchPlaces(matching: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func useCurrentLocation() {
        Task {
            isLocating = true
            errorMessage = nil
            defer { isLocating = false }

            do {
                let location = try await locationService.requestCurrentLocation()
                selectedDraft = DeliveryAddressDraft(
                    label: "Current Location",
                    title: "Current Location",
                    formattedAddress: "Current location",
                    latitude: location.latitude,
                    longitude: location.longitude,
                    coordinateSource: .deviceLocation,
                    accuracy: location.horizontalAccuracyM
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DeliveryAddressDraft: Hashable {
    var label: String
    let title: String
    let formattedAddress: String
    var latitude: Double
    var longitude: Double
    let coordinateSource: DeliveryCoordinateSource
    let accuracy: Double?
}

private struct DeliveryPinConfirmationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: DeliveryAddressDraft
    let onSave: (SavedAddress) -> Void
    let onBack: () -> Void
    @State private var region: MKCoordinateRegion
    @State private var label: String
    @State private var apartmentUnit = ""
    @State private var note = ""
    @State private var quote: CustomerV2DeliveryQuotePayload?
    @State private var isQuoting = false
    @State private var errorMessage: String?

    init(draft: DeliveryAddressDraft, onSave: @escaping (SavedAddress) -> Void, onBack: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _label = State(initialValue: draft.label)
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        ))
        self.onSave = onSave
        self.onBack = onBack
    }

    private var pin: [DeliveryMapPin] {
        [DeliveryMapPin(latitude: draft.latitude, longitude: draft.longitude)]
    }

    private var canSave: Bool {
        quote?.deliverable == true
            && quote?.deliveryZoneId != nil
            && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FBSpacing.md) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(FBColors.cookieOrange)
            }
            .buttonStyle(.plain)

            Map(coordinateRegion: $region, annotationItems: pin) { item in
                MapMarker(coordinate: item.coordinate, tint: FBColors.cookieOrange)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))
            .overlay(RoundedRectangle(cornerRadius: FBCorner.card).stroke(FBColors.line.opacity(0.7)))
            .onChange(of: region.center.latitude) { _, _ in updateDraftFromRegion() }
            .onChange(of: region.center.longitude) { _, _ in updateDraftFromRegion() }

            VStack(alignment: .leading, spacing: 5) {
                Text(draft.title)
                    .font(.custom("AvenirNext-DemiBold", size: 18))
                    .foregroundStyle(FBColors.charcoal)
                Text(draft.formattedAddress)
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(FBColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                DeliveryTextField(title: "Label", text: $label, prompt: "Home, Office, Gym")
                DeliveryTextField(title: "Apartment / unit / floor", text: $apartmentUnit, prompt: "Optional")
                DeliveryTextField(title: "Delivery notes", text: $note, prompt: "Optional")
            }

            quoteStateView

            Spacer(minLength: 0)

            FBPrimaryButton(title: canSave ? "Save delivery address" : "Check delivery", systemImage: canSave ? "checkmark" : "location.magnifyingglass") {
                if canSave {
                    saveAddress()
                } else {
                    quoteAddress()
                }
            }
            .disabled(isQuoting)
            .opacity(isQuoting ? 0.6 : 1)
        }
        .padding(FBSpacing.md)
        .onAppear {
            quoteAddress()
        }
    }

    @ViewBuilder
    private var quoteStateView: some View {
        if isQuoting {
            checkoutStatusCard(title: "Checking delivery", message: "Asking Fitbites for the real zone and fee.", color: FBColors.cookieOrange)
        } else if let quote, quote.deliverable, let zoneName = quote.zoneName, let fee = quote.deliveryFee?.value {
            checkoutStatusCard(title: zoneName, message: "Delivery fee: \(fee.vndText)", color: FBColors.cookieOrange)
        } else if let quote, !quote.deliverable {
            checkoutStatusCard(title: "Sorry", message: "Fitbites does not currently deliver to this location.", color: .red)
        } else if let errorMessage {
            checkoutStatusCard(title: "Quote failed", message: errorMessage, color: .red)
        }
    }

    private func checkoutStatusCard(title: String, message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 13))
                .foregroundStyle(color)
            Text(message)
                .font(.custom("AvenirNext-Regular", size: 12))
                .foregroundStyle(FBColors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.compact))
    }

    private func updateDraftFromRegion() {
        draft.latitude = region.center.latitude
        draft.longitude = region.center.longitude
        quote = nil
    }

    private func quoteAddress() {
        Task {
            isQuoting = true
            errorMessage = nil
            defer { isQuoting = false }

            do {
                quote = try await appState.quoteDeliveryAddress(
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    accuracy: draft.accuracy,
                    coordinateSource: draft.coordinateSource
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAddress() {
        guard let quote, quote.deliverable, let zoneID = quote.deliveryZoneId else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = apartmentUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(SavedAddress(
            id: UUID().uuidString,
            label: trimmedLabel,
            detail: draft.formattedAddress,
            note: trimmedNote,
            systemImage: "mappin.and.ellipse",
            latitude: draft.latitude,
            longitude: draft.longitude,
            coordinateSource: draft.coordinateSource,
            locationAccuracyM: draft.coordinateSource == .deviceLocation ? draft.accuracy : nil,
            apartmentUnit: unit.isEmpty ? nil : unit,
            deliveryZoneID: zoneID,
            deliveryZoneName: quote.zoneName,
            lastQuotedDeliveryFeeVND: quote.deliveryFee?.value
        ))
    }
}

private struct DeliveryMapPin: Identifiable {
    let id = UUID()
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct DeliveryTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("AvenirNext-Regular", size: 10))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(FBColors.muted)
            TextField(prompt, text: $text)
                .font(.custom("AvenirNext-Regular", size: 15))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(FBColors.surface, in: RoundedRectangle(cornerRadius: FBCorner.compact))
                .overlay(RoundedRectangle(cornerRadius: FBCorner.compact).stroke(FBColors.line.opacity(0.58)))
        }
    }
}

private struct CartLineRow: View {
    @EnvironmentObject private var appState: AppState
    let line: CartLine
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProductImageTile(imageName: line.product.imageName, imageURL: line.product.imageURL)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: FBCorner.card))

            VStack(alignment: .leading, spacing: 4) {
                Text(line.product.name)
                    .font(.fbBody(.semibold))
                    .foregroundStyle(FBColors.charcoal)
                Text(line.optionSummary)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .tracking(0.8)
                    .foregroundStyle(FBColors.muted)
                    .lineLimit(2)
                Text(line.unitPriceVND.vndText)
                    .font(.fbCaption(.bold))
                    .foregroundStyle(FBColors.cookieOrange)
            }

            Spacer()

            StepperControls(
                quantity: line.quantity,
                onDecrease: {
                    withAnimation(.snappy) { appState.cart.decrease(line) }
                },
                onIncrease: {
                    withAnimation(.snappy) { appState.cart.increase(line) }
                }
            )
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .overlay(FBColors.line.opacity(0.48))
                    .padding(.leading, 74)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                appState.cart.remove(line)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

private struct StepperControls: View {
    let quantity: Int
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .frame(width: 30, height: 30)
                    .background(FBColors.surface, in: Circle())
                    .overlay(Circle().stroke(FBColors.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease quantity")

            Text("\(quantity)")
                .font(.fbBody(.bold))
                .frame(width: 22)

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(FBColors.cookieOrange, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase quantity")
        }
    }
}

private struct QuoteRow: View {
    let label: String
    let value: String
    var isStrong = false

    var body: some View {
        HStack {
            Text(label)
                .font(isStrong ? .fbHeadline(.bold) : .fbBody(.semibold))
            Spacer()
            Text(value)
                .font(isStrong ? .fbHeadline(.bold) : .fbBody(.semibold))
        }
        .foregroundStyle(FBColors.charcoal)
    }
}
