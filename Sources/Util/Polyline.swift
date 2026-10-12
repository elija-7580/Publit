import Foundation

enum Polyline {
    /// Decodes a Google encoded polyline with the given decimal precision.
    static func decode(_ encoded: String, precision: Int) -> [LatLon] {
        let bytes = Array(encoded.utf8)
        let factor = pow(10.0, Double(precision))
        var coords: [LatLon] = []
        var index = 0
        var lat = 0
        var lon = 0

        func next() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coords.append(LatLon(lat: Double(lat) / factor, lon: Double(lon) / factor))
        }
        return coords
    }

    /// Fewer points for drawing on a map (Douglas-Peucker). A route is drawn with a few hundred
    /// points instead of thousands; nothing visible changes at street zoom.
    static func simplify(_ points: [LatLon], toleranceMeters: Double = 4) -> [LatLon] {
        guard points.count > 2 else { return points }
        let lat0 = points[0].lat * .pi / 180
        let mx = 111_320 * cos(lat0), my = 110_540.0
        let xs = points.map { $0.lon * mx }, ys = points.map { $0.lat * my }
        let tol2 = toleranceMeters * toleranceMeters
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let dx = xs[b] - xs[a], dy = ys[b] - ys[a]
            let len2 = dx * dx + dy * dy
            var worst = -1.0, index = a
            for i in (a + 1)..<b {
                let px = xs[i] - xs[a], py = ys[i] - ys[a]
                let d2: Double
                if len2 == 0 {
                    d2 = px * px + py * py
                } else {
                    let t = max(0, min(1, (px * dx + py * dy) / len2))
                    let ex = px - t * dx, ey = py - t * dy
                    d2 = ex * ex + ey * ey
                }
                if d2 > worst { worst = d2; index = i }
            }
            if worst > tol2 {
                keep[index] = true
                stack.append((a, index)); stack.append((index, b))
            }
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }
}
