import SwiftUI
import UIKit

@main
struct MyFitbitesApp: App {
    @StateObject private var appState = MyFitbitesApp.makeAppState()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 72 * 1024 * 1024,
            diskCapacity: 320 * 1024 * 1024,
            diskPath: "myfitbites-image-cache"
        )

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(red: 0.992, green: 0.968, blue: 0.918, alpha: 1)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
    }

    private static func makeAppState() -> AppState {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true

        let client = CustomerV2APIClient(session: URLSession(configuration: configuration))

        return AppState(
            dashboardRepository: APIBackedDashboardRepository(client: client, fallback: LocalDashboardRepository()),
            catalogRepository: APIBackedCatalogRepository(client: client, fallback: LocalCatalogRepository()),
            rewardsRepository: APIBackedRewardsRepository(client: client, fallback: LocalRewardsRepository()),
            customerAPIClient: client
        )
    }
}
