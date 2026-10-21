import Foundation
import XCTest
@testable import Publit

final class TransferOverviewTests: XCTestCase {
    private func itinerary() throws -> Itinerary {
        let response = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps"))
        return try XCTUnwrap(response.itineraries.first)
    }

    func testTransferContainsBothVehiclesAndEndpointTimes() throws {
        let it = try itinerary()
        let info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertEqual(info.fromLine, "U4")
        XCTAssertEqual(info.toLine, "U6")
        XCTAssertEqual(info.arrivalStop, it.legs[1].to)
        XCTAssertEqual(info.departureStop, it.legs[3].from)
        XCTAssertEqual(info.arrivalTime, it.legs[1].endTime)
        XCTAssertEqual(info.departureTime, it.legs[3].startTime)
        XCTAssertEqual(info.arrivalIsLive, it.legs[1].realTime)
        XCTAssertEqual(info.departureIsLive, it.legs[3].realTime)
        XCTAssertEqual(info.fromDirection, it.legs[1].shownDirection)
        XCTAssertEqual(info.toDirection, it.legs[3].shownDirection)
        XCTAssertEqual(info.connectionSeconds, 240)
        XCTAssertEqual(info.walkSeconds, 180)
        XCTAssertEqual(info.spareSeconds, 60)
        XCTAssertFalse(info.changesStation, "Different platforms at Odeonsplatz are one station")
        XCTAssertFalse(info.isCancelled)
        XCTAssertFalse(info.isMissed)
    }

    func testLiveDelayCanBreakConnectionWithoutClampingNegativeBuffer() throws {
        var it = try itinerary()
        it.legs[1].endTime = it.legs[1].endTime.addingTimeInterval(120)
        it.legs[1].realTime = true
        it.legs[3].realTime = false
        let info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertEqual(info.connectionSeconds, 120)
        XCTAssertEqual(info.spareSeconds, -60)
        XCTAssertTrue(info.isMissed)
        XCTAssertTrue(info.arrivalIsLive)
        XCTAssertFalse(info.departureIsLive)
    }

    func testEventLevelTimeSourceOverridesBroadLegFlag() throws {
        var it = try itinerary()
        it.legs[1].realTime = true
        it.legs[1].to.arrivalTimestampReason = "NO_RT_DATA"
        it.legs[3].realTime = true
        it.legs[3].from.departureTimestampReason = "PREDICTED"
        var info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertFalse(info.arrivalIsLive)
        XCTAssertTrue(info.departureIsLive)
        it.legs[3].from.departureTimestampReason = "INCONSISTENT_RT"
        XCTAssertFalse(try XCTUnwrap(TransferInfo(before: 3, in: it)).departureIsLive)
        it.legs[1].liveSource = "ÖBB"
        info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertTrue(info.arrivalIsLive, "A live overlay supersedes original router provenance")
    }

    func testMissingAndChangedPlatforms() throws {
        var it = try itinerary()
        it.legs[1].to.track = nil
        it.legs[3].from.track = nil
        var info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertNil(info.platforms)
        XCTAssertNil(info.fromTrack)
        XCTAssertNil(info.toTrack)
        it.legs[1].to.track = "54"
        info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertEqual(info.platforms, "From platform 54")
        it.legs[3].from.track = "52"
        info = try XCTUnwrap(TransferInfo(before: 3, in: it))
        XCTAssertEqual(info.departureStop.platformChange?.scheduled, "51")
        XCTAssertEqual(info.departureStop.platformChange?.now, "52")
    }

    func testStationChangeAndServiceCancellation() throws {
        var it = try itinerary()
        // A real station change, not just two platforms of one station.
        it.legs[3].from = it.legs[3].to
        XCTAssertTrue(try XCTUnwrap(TransferInfo(before: 3, in: it)).changesStation)
        it.legs[3].cancelled = true
        XCTAssertTrue(try XCTUnwrap(TransferInfo(before: 3, in: it)).isCancelled)
        it.legs[3].cancelled = false
        it.legs[3].from.cancelled = true
        XCTAssertTrue(try XCTUnwrap(TransferInfo(before: 3, in: it)).isCancelled)
    }

    func testOnlyActualChangesHaveAnOverview() throws {
        let it = try itinerary()
        for index in [-1, 0, 1, 2, 4, 999] { XCTAssertNil(TransferInfo(before: index, in: it)) }
        var noWalk = it
        noWalk.legs.remove(at: 2)
        let info = try XCTUnwrap(TransferInfo(before: 2, in: noWalk))
        XCTAssertEqual(info.walkSeconds, 0)
        XCTAssertEqual(info.spareSeconds, info.connectionSeconds)
    }
}

final class TrainDivisionTests: XCTestCase {
    private func alert(_ text: String) -> Alert { Alert(headerText: "Operator", descriptionText: text, url: "https://example.org/notice") }

    private func rail() throws -> Leg {
        let it = try TransitousClient.makeDecoder().decode(Itinerary.self, from: Fixtures.data("trip_s3"))
        return try XCTUnwrap(it.legs.first(where: \.isTransit))
    }

    func testExplicitOperatorWordingInGermanEnglishFrenchAndItalian() {
        for text in ["Zugteilung in München", "Flügelung: Zugteile beachten", "Der Zug wird in Rosenheim geteilt.",
                     "This train splits at the next station.", "The train will be split at A.",
                     "Train division", "Le train sera divisé à A.", "Il treno viene diviso a A."] {
            XCTAssertTrue(alert(text).isTrainDivisionInfo, text)
        }
    }

    func testDoesNotInferDivisionFromDestinationsOrGenericDisruptions() {
        for text in ["Train to Split", "Split tickets available", "Platform change", "Train cancelled", "Two destinations: A / B", "Zug fällt aus"] {
            XCTAssertFalse(alert(text).isTrainDivisionInfo, text)
        }
    }

    func testRetainsSourceTextAndURLWithoutInferringCarriageData() throws {
        var leg = try rail()
        let source = alert("Zugteilung in A. Vorderer Zugteil nach B, hinterer Zugteil nach C.")
        leg.alerts = [source, source, alert("Platform change")]
        XCTAssertEqual(leg.trainDivisionAlerts, [source], "One deduplicated original notice, including link")
        leg.alerts = nil
        XCTAssertEqual(leg.trainDivisionAlerts, [])
    }

    func testIntermediateStopNoticesAreIncludedButExpiredOnesAreNot() throws {
        var leg = try rail()
        let source = alert("Train division")
        leg.from.alerts = [source]
        XCTAssertEqual(leg.trainDivisionAlerts, [source])
        var expired = source
        expired.communicationPeriod = [AlertPeriod(start: nil, end: Date(timeIntervalSince1970: 1))]
        leg.from.alerts = [expired]
        XCTAssertEqual(leg.trainDivisionAlerts, [])
    }

    func testOrdinaryBusDoesNotGainATrainDivisionNotice() throws {
        // Use the established fixture encoder to change the immutable transport mode.
        var railLeg = try rail()
        railLeg.alerts = [alert("Train division")]
        let data = try JSONFile<Itinerary>.encoder.encode(railLeg)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["mode"] = "BUS"
        let bus = try TransitousClient.makeDecoder().decode(Leg.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(bus.trainDivisionAlerts, [])
    }
}
