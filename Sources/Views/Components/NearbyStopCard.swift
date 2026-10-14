import SwiftUI

struct NearbyStopCard: View {
    let group: StopGroup
    var nearest = false
    var from: LatLon? = nil
    @State private var walkSeconds: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                StopDeparturesView(stopId: group.id, name: group.name, coordinate: group.coordinate, exact: group.isPole)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: group.name).font(.title3.weight(.bold)).lineLimit(2)
                    HStack(spacing: 4) {
                        if nearest { SignatureDot(size: 7) }
                        if let distance = group.distance {
                            Text(verbatim: Fmt.distance(meters: distance))
                        }
                        if let walkSeconds {
                            Text(verbatim: "· " + L10n.f("%lld min walk", max(1, Int(ceil(walkSeconds / 60)))))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if group.isPole, !group.directions.isEmpty {
                        Text(verbatim: group.directions.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).contentShape(Rectangle())
            }
            ForEach(group.departures.prefix(5)) { st in
                Divider().padding(.leading, 16)
                NavigationLink(value: TripTarget(stopTime: st, stationId: group.id, stationName: group.name, coordinate: group.coordinate)) {
                    DepartureRow(stopTime: st).padding(.horizontal, 16).padding(.vertical, 5)
                }
            }
            Divider().padding(.leading, 16)
            NavigationLink {
                StopDeparturesView(stopId: group.id, name: group.name, coordinate: group.coordinate, exact: group.isPole)
            } label: {
                HStack {
                    Text("All departures").font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.ink)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task(id: from.map { "\(Int($0.lat * 10000))|\(Int($0.lon * 10000))" }) {
            guard let from else { return }
            let seconds = await WalkingTimes.shared.seconds(from: from, to: group.coordinate)
            guard !Task.isCancelled else { return }
            walkSeconds = seconds
        }
    }
}
