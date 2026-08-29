@MainActor
protocol DashboardRepository {
    func dashboard() -> CustomerDashboard
}

@MainActor
protocol CatalogRepository {
    func catalog() -> StoreCatalog
}

@MainActor
protocol RewardsRepository {
    func rewards() -> RewardsProgress
}

@MainActor
protocol CustomerDataRefreshing {
    func refresh() async
}

@MainActor
protocol CustomerV2DashboardPayloadCaching {
    func applyDashboardPayload(_ payload: CustomerV2DashboardPayload)
}
