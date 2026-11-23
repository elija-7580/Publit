import Foundation

/// A saved place or stop. Stored locally on the device only.
struct SavedPlace: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var subtitle: String?
    var lat: Double
    var lon: Double
    var stopId: String?
    var role: PlaceRole?
    /// One street stop only (one side of the road), not the whole station.
    var exact: Bool? = nil

    var isStop: Bool { stopId != nil }

    /// Same saved thing: same ID, or the same station reached via a different stop ID
    /// (search returns one platform, Nearby another).
    func isSame(as other: SavedPlace) -> Bool {
        if id == other.id {
            // A stop is known by its ID. An address ID is not unique: the search can hand out the
            // same one for two addresses, so two addresses are the same only at the same spot.
            if isStop || other.isStop { return true }
            return coordinate.distance(to: other.coordinate) < Self.sameSpotRadius
        }
        guard isStop, other.isStop else { return false }
        if stopId == other.stopId { return true }
        // The stop across the road has the same name but other departures.
        if exact == true || other.exact == true { return false }
        return StopGrouping.normalizedName(name) == StopGrouping.normalizedName(other.name)
            && coordinate.distance(to: other.coordinate) < StopGrouping.mergeRadius
    }
    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }

    /// Two addresses with the same ID closer than this (metres) are one saved place.
    static let sameSpotRadius: Double = 30

    /// A stable ID of its own for an address whose ID another saved address already has.
    var ownID: String { "\(id)|\(String(format: "%.5f,%.5f", lat, lon))" }

    /// The same saved thing, also when this address was saved under its own ID (`ownID`).
    func isSaved(as saved: SavedPlace) -> Bool {
        saved.isSame(as: self) || (!isStop && saved.id == ownID)
    }

    init(id: String, name: String, subtitle: String?, lat: Double, lon: Double, stopId: String?) {
        self.id = id; self.name = name; self.subtitle = subtitle
        self.lat = lat; self.lon = lon; self.stopId = stopId
    }

    init(match: GeocodeMatch) {
        self.init(id: match.id, name: match.name, subtitle: match.subtitle,
                  lat: match.lat, lon: match.lon, stopId: match.isStop ? match.id : nil)
    }

    init(stop place: Place) {
        let sid = place.stationId
        self.init(id: sid, name: place.name, subtitle: nil, lat: place.lat, lon: place.lon, stopId: sid)
    }
}
