import Foundation

enum DashboardHeroScene: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case night
    case rain
    case thunderstorm

    var id: String { rawValue }

    var assetName: String {
        switch self {
        case .morning:
            "hero_morning"
        case .afternoon:
            "hero_afternoon"
        case .evening:
            "hero_evening"
        case .night:
            "hero_night"
        case .rain:
            "hero_rain"
        case .thunderstorm:
            "hero_thunderstorm"
        }
    }
}

enum DashboardHeroWeatherCondition: Equatable {
    case rain
    case thunderstorm
}

protocol DashboardHeroWeatherProviding {
    var currentCondition: DashboardHeroWeatherCondition? { get }
    func refreshIfNeeded() async
}

struct UnavailableDashboardHeroWeatherProvider: DashboardHeroWeatherProviding {
    var currentCondition: DashboardHeroWeatherCondition? { nil }

    func refreshIfNeeded() async {}
}

struct DashboardHeroResolver {
    var calendar: Calendar = .current

    func resolve(
        at date: Date = Date(),
        weatherCondition: DashboardHeroWeatherCondition? = nil
    ) -> DashboardHeroScene {
        switch weatherCondition {
        case .thunderstorm:
            return .thunderstorm
        case .rain:
            return .rain
        case .none:
            return timeScene(at: date)
        }
    }

    private func timeScene(at date: Date) -> DashboardHeroScene {
        let hour = calendar.component(.hour, from: date)

        switch hour {
        case 5..<11:
            return .morning
        case 11..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }
}
