import MapKit
import SwiftUI
import UIKit

/// An area with missing timetable data on the map: an outline (with holes) ...
final class CoveragePolygon: MKPolygon {
    var level = CoverageLevel.partial
}

/// ... or a circle around a big city.
final class CoverageCircle: MKCircle {
    var level = CoverageLevel.partial
}

/// The "Data gaps" layer: every area of the coverage atlas as a translucent orange shape,
/// so a map never looks complete where the timetable data is not.
enum CoverageOverlays {
    /// One overlay per piece of every area, the worst first (lighter shapes end up on top).
    static func make(_ atlas: CoverageAtlas = .shared) -> [MKOverlay] {
        var out: [MKOverlay] = []
        for area in atlas.areas.sorted(by: { $0.level > $1.level }) {
            switch area.shape {
            case .circle(let center, let radius):
                let circle = CoverageCircle(center: center.clCoordinate, radius: radius)
                circle.level = area.level
                out.append(circle)
            case .polygon:
                for piece in area.pieces {
                    let holes = piece.holes.map { ring in
                        MKPolygon(coordinates: ring.map(\.clCoordinate), count: ring.count)
                    }
                    let outer = piece.outer.map(\.clCoordinate)
                    let polygon = CoveragePolygon(coordinates: outer, count: outer.count, interiorPolygons: holes.isEmpty ? nil : holes)
                    polygon.level = area.level
                    out.append(polygon)
                }
            }
        }
        return out
    }

    /// No data at all is filled stronger and drawn with a solid edge; a part missing has a dashed one.
    static func style(_ renderer: MKOverlayPathRenderer, level: CoverageLevel) {
        let orange = UIColor(Color.delay)
        renderer.fillColor = orange.withAlphaComponent(level == .none ? 0.26 : 0.17)
        renderer.strokeColor = orange.withAlphaComponent(0.9)
        renderer.lineWidth = 1.5
        renderer.lineDashPattern = level == .none ? nil : [6, 4]
    }
}
