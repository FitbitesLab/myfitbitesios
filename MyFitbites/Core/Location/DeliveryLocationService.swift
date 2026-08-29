import CoreLocation
import Foundation
import MapKit

struct DeliveryPlaceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let formattedAddress: String
    let latitude: Double
    let longitude: Double

    var savedAddressDetail: String {
        formattedAddress.isEmpty ? [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ") : formattedAddress
    }
}

struct DeliveryDeviceLocation: Hashable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyM: Double
}

enum DeliveryLocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable
    case searchFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Location permission is needed to use your current location."
        case .locationUnavailable:
            "Fitbites could not read your current location."
        case .searchFailed:
            "Fitbites could not search that address."
        }
    }
}

@MainActor
final class DeliveryLocationService: NSObject, ObservableObject {
    private static let fitbitesCenter = CLLocationCoordinate2D(latitude: 10.8042, longitude: 106.7333)
    private static let localSearchRadiusMeters: CLLocationDistance = 35_000
    private static let localSearchRegion = MKCoordinateRegion(
        center: fitbitesCenter,
        latitudinalMeters: localSearchRadiusMeters * 2,
        longitudinalMeters: localSearchRadiusMeters * 2
    )

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<DeliveryDeviceLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func searchPlaces(matching query: String) async throws -> [DeliveryPlaceSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let shouldSearchBroadly = queryNamesNonLocalCity(trimmedQuery)

        if !shouldSearchBroadly {
            let localMapItems = try await localSearchMapItems(matching: trimmedQuery)
            let localResults = rankedResults(from: localMapItems)
                .filter { $0.distanceFromFitbites <= Self.localSearchRadiusMeters }

            if !localResults.isEmpty {
                return Array(localResults.prefix(12).map(\.result))
            }
        }

        let globalMapItems = try await mapItems(matching: trimmedQuery, region: nil)
        return Array(rankedResults(from: globalMapItems).prefix(12).map(\.result))
    }

    private func localSearchMapItems(matching query: String) async throws -> [MKMapItem] {
        let queryVariants = [
            query,
            "\(query) Ho Chi Minh City Vietnam",
            "\(query) Thao Dien Ho Chi Minh City Vietnam"
        ]

        var results: [MKMapItem] = []
        for queryVariant in queryVariants {
            results.append(contentsOf: try await mapItems(matching: queryVariant, region: Self.localSearchRegion))
        }

        return results
    }

    private func mapItems(matching query: String, region: MKCoordinateRegion?) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let region {
            request.region = region
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems
        } catch {
            throw DeliveryLocationError.searchFailed
        }
    }

    private func rankedResults(from mapItems: [MKMapItem]) -> [(result: DeliveryPlaceSearchResult, distanceFromFitbites: CLLocationDistance)] {
        Dictionary(grouping: mapItems) { item in
            let coordinate = item.placemark.coordinate
            return "\(coordinate.latitude.rounded(toPlaces: 5)),\(coordinate.longitude.rounded(toPlaces: 5))"
        }
        .compactMap { _, groupedItems in groupedItems.first }
        .compactMap { item -> (result: DeliveryPlaceSearchResult, distanceFromFitbites: CLLocationDistance)? in
            let placemark = item.placemark
            let coordinate = placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(
                    latitude: Self.fitbitesCenter.latitude,
                    longitude: Self.fitbitesCenter.longitude
                ))

            return (
                result: DeliveryPlaceSearchResult(
                    title: item.name ?? placemark.name ?? "Selected location",
                    subtitle: subtitle(for: placemark),
                    formattedAddress: address(for: placemark),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                distanceFromFitbites: distance
            )
        }
        .sorted { first, second in
            let firstLocal = first.distanceFromFitbites <= Self.localSearchRadiusMeters
            let secondLocal = second.distanceFromFitbites <= Self.localSearchRadiusMeters

            if firstLocal != secondLocal {
                return firstLocal
            }

            return first.distanceFromFitbites < second.distanceFromFitbites
        }
    }

    func requestCurrentLocation() async throws -> DeliveryDeviceLocation {
        let status = manager.authorizationStatus

        if status == .denied || status == .restricted {
            throw DeliveryLocationError.permissionDenied
        }

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func subtitle(for placemark: MKPlacemark) -> String {
        [placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func address(for placemark: MKPlacemark) -> String {
        [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private func queryNamesNonLocalCity(_ query: String) -> Bool {
        let normalized = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return [
            "ha noi",
            "hanoi",
            "da nang",
            "danang",
            "nha trang",
            "can tho"
        ].contains { normalized.contains($0) }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension DeliveryLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in
                locationContinuation?.resume(throwing: DeliveryLocationError.locationUnavailable)
                locationContinuation = nil
            }
            return
        }

        Task { @MainActor in
            locationContinuation?.resume(returning: DeliveryDeviceLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracyM: location.horizontalAccuracy
            ))
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: DeliveryLocationError.locationUnavailable)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted else { return }

        Task { @MainActor in
            locationContinuation?.resume(throwing: DeliveryLocationError.permissionDenied)
            locationContinuation = nil
        }
    }
}
