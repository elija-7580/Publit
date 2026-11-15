import MapKit

/// Addresses and places from Apple Maps, for the place search next to Transitous.
///
/// Transitous' geocoder (OpenStreetMap) often lacks house numbers, and in many towns whole
/// streets; people could not set their own street and number as Home. Apple's address data
/// fills that gap. The map already shows Apple Maps and its search already asked Apple, so no
/// new party learns anything: only the typed text and the area around the position go to Apple.
enum AppleSearch {
    /// - Parameters:
    ///   - near: centre of the area to prefer (about 50 km); nil to search everywhere.
    ///   - addresses: include street addresses.
    ///   - places: include points of interest (shops, sights, airports…).
    static func places(_ text: String, near: LatLon?, addresses: Bool = true, places: Bool = true) async -> [GeocodeMatch] {
        guard addresses || places else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        var types: MKLocalSearch.ResultType = []
        if addresses { types.insert(.address) }
        if places { types.insert(.pointOfInterest) }
        request.resultTypes = types
        if let near, near.isValidCoordinate {
            request.region = MKCoordinateRegion(center: near.clCoordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(12).compactMap { match($0, fallbackName: text) }
    }

    /// An Apple result in the shape of a geocoder hit. Without a point-of-interest category it is an address.
    static func match(_ item: MKMapItem, fallbackName: String) -> GeocodeMatch? {
        let c = item.placemark.coordinate
        let point = LatLon(lat: c.latitude, lon: c.longitude)
        guard point.isValidCoordinate else { return nil }
        let mark = item.placemark
        let name = item.name ?? fallbackName
        if item.pointOfInterestCategory == nil, mark.thoroughfare != nil {
            return GeocodeMatch(type: "ADDRESS", name: name, id: GeocodeMatch.pickedId(point), lat: point.lat, lon: point.lon,
                                street: mark.thoroughfare, houseNumber: mark.subThoroughfare, country: mark.isoCountryCode,
                                areas: mark.locality.map { [GeocodeArea(name: $0, adminLevel: 8, default: true)] } ?? [],
                                category: nil)
        }
        return TransitMapView.Coordinator.match(item, name: name, at: point)
    }
}
