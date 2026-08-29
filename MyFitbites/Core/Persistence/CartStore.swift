import Foundation

struct CartStore {
    private(set) var lines: [CartLine] = []

    var itemCount: Int {
        lines.reduce(0) { $0 + $1.quantity }
    }

    var subtotalVND: Int {
        lines.reduce(0) { $0 + $1.totalVND }
    }

    mutating func add(_ product: StoreProduct, toppings: [StoreTopping] = [], quantity: Int = 1) {
        let sortedToppings = toppings.sorted { $0.toppingID < $1.toppingID }
        if let index = lines.firstIndex(where: { line in
            line.product.inventoryItemID == product.inventoryItemID
                && line.toppings.map(\.toppingID) == sortedToppings.map(\.toppingID)
        }) {
            lines[index].quantity += quantity
        } else {
            lines.append(CartLine(id: UUID(), product: product, toppings: sortedToppings, quantity: quantity))
        }
    }

    mutating func increase(_ line: CartLine) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[index].quantity += 1
    }

    mutating func decrease(_ line: CartLine) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        if lines[index].quantity <= 1 {
            lines.remove(at: index)
        } else {
            lines[index].quantity -= 1
        }
    }

    mutating func remove(_ line: CartLine) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines.remove(at: index)
    }

    mutating func clear() {
        lines.removeAll()
    }
}

extension Int {
    var vndText: String {
        "\(formatted())d"
    }
}
