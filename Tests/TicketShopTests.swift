// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import XCTest
@testable import Publit

final class PartnerLinkTests: XCTestCase {
    private let programs = [
        PartnerProgram(name: "Deutsche Bahn", hosts: ["bahn.de"], template: "https://www.awin1.com/cread.php?awinmid=1&awinaffid=2&ued={url}"),
        PartnerProgram(name: "Off", hosts: ["oebb.at"], template: ""),
    ]

    func testShopLinkGoesThroughItsProgram() throws {
        let wrapped = try XCTUnwrap(PartnerLinks.wrap(URL(string: "https://int.bahn.de/en?x=1&y=2")!, in: programs))
        XCTAssertEqual(wrapped.host, "www.awin1.com")
        let ued = URLComponents(url: wrapped, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ued" }?.value
        XCTAssertEqual(ued, "https://int.bahn.de/en?x=1&y=2")
    }

    func testOtherShopsAndEmptyProgramsStayUnchanged() {
        XCTAssertNil(PartnerLinks.wrap(URL(string: "https://tickets.oebb.at")!, in: programs))
        XCTAssertNil(PartnerLinks.wrap(URL(string: "https://notbahn.de")!, in: programs))
        XCTAssertNil(PartnerLinks.wrap(URL(string: "myapp://bahn.de")!, in: programs))
    }

    func testNoProgramIsActiveUntilFilledIn() {
        XCTAssertTrue(PartnerLinks.builtIn.allSatisfy { $0.template.isEmpty || $0.template.hasPrefix("https://") })
    }

    func testProgramsFromTheLinkServiceReplaceTheBuiltInList() throws {
        let json = """
        {"programs":[{"id":"flixbus","name":"FlixBus","hosts":["flixbus.de"],"template":"https://www.awin1.com/cread.php?awinmid=1&awinaffid=2&ued={url}"},
                     {"id":"x","name":"Bad","hosts":["x.de"],"template":"http://x.de/{url}"},
                     {"id":"y","name":"Twice","hosts":["y.de"],"template":"https://y.de/{url}{url}"}]}
        """
        let list = try XCTUnwrap(PartnerLinks.decode(Data(json.utf8)))
        XCTAssertEqual(list.map(\.name), ["FlixBus"])
        XCTAssertNil(PartnerLinks.decode(Data("nope".utf8)))
        PartnerLinks.set(list)
        defer { PartnerLinks.set(nil) }
        XCTAssertEqual(PartnerLinks.wrap(URL(string: "https://shop.flixbus.de/x")!)?.host, "www.awin1.com")
        XCTAssertNil(PartnerLinks.wrap(URL(string: "https://int.bahn.de")!))
    }
}

final class TicketShopTests: XCTestCase {
    private func itinerary() throws -> Itinerary {
        let plan = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan"))
        return try XCTUnwrap(plan.itineraries.first { it in it.legs.contains { $0.isTransit } })
    }

    func testShopIsOffWithoutAnHTTPSAddress() {
        XCTAssertNil(TicketShop.validURL(nil))
        XCTAssertNil(TicketShop.validURL("$(TICKET_SHOP_URL)"))
        XCTAssertNil(TicketShop.validURL("http://shop.example"))
        XCTAssertNotNil(TicketShop.validURL("https://shop.example"))
    }

    func testRequestHasOnlyTransitLegsWithTheirPositions() throws {
        let it = try itinerary()
        let request = TicketShop.request(for: it, adults: 2, locale: "de-AT")
        XCTAssertFalse(request.legs.isEmpty)
        XCTAssertEqual(request.adults, 2)
        XCTAssertEqual(request.locale, "de")
        for leg in request.legs {
            XCTAssertTrue(it.legs[leg.index].isTransit)
            XCTAssertEqual(leg.departure, it.legs[leg.index].startTime)
        }
        let json = String(decoding: try TicketShopClient.makeEncoder().encode(request), as: UTF8.self)
        XCTAssertTrue(json.contains("\"departure\":\"20"), json)
    }

    func testBoughtTicketBecomesAPass() throws {
        let json = """
        {"status":"booked","amountCharged":1290,"currency":"EUR","items":[{"leg":1,"status":"booked","amount":1290,"tickets":[
         {"title":"Basic","operator":"FlixBus","origin":"Wien","destination":"Graz","validFrom":"2026-12-01T08:00:00Z",
          "validUntil":"2026-12-01T10:30:00.000Z","passenger":"Ana Muster","reference":"B-1","barcode":{"format":"qr","message":"X1"},"pdf":null}]}]}
        """
        let result = try TicketShopClient.makeDecoder().decode(OrderResult.self, from: Data(json.utf8))
        let ticket = try XCTUnwrap(result.items.first?.tickets.first)
        let pass = ticket.pass(symbol: TicketPass.Symbol(mode: "COACH"), price: "€ 12,90", tripId: "t1")
        XCTAssertEqual(pass.operatorName, "FlixBus")
        XCTAssertEqual(pass.symbol, .bus)
        XCTAssertEqual(pass.barcode?.format, .qr)
        XCTAssertEqual(pass.barcode?.message, "X1")
        XCTAssertEqual(pass.tripId, "t1")
        XCTAssertNotNil(pass.validUntil)
    }

    func testServerErrorsBecomeReadableMessages() throws {
        let failure = try JSONDecoder().decode(ShopFailure.self, from: Data(#"{"error":"expired","message":"x"}"#.utf8))
        XCTAssertEqual(failure.errorDescription, L10n.t("The prices have expired. Please check them again."))
    }

    func testPaymentReturnMatchesTheOrder() async throws {
        let it = try itinerary()
        await MainActor.run {
            let model = CheckoutModel(itinerary: it, client: TicketShopClient(baseURL: URL(string: "https://shop.example")!))
            XCTAssertFalse(model.paymentReturned(URL(string: "publit://shop/return?cancelled=1")))
            XCTAssertFalse(model.paymentReturned(nil))
            XCTAssertEqual(model.phase, .ready)
        }
    }

    func testOwnRouterIsUsedOnlyWithACompleteHttpsAddress() {
        XCTAssertEqual(TransitousClient.router("https://route.example.org")?.host, "route.example.org")
        XCTAssertNil(TransitousClient.router(nil))
        XCTAssertNil(TransitousClient.router(""))
        XCTAssertNil(TransitousClient.router("$(ROUTER_URL)"))
        XCTAssertNil(TransitousClient.router("http://route.example.org"))
        // The test bundle sets no router, so the app keeps using Transitous.
        XCTAssertEqual(TransitousClient.routerURL, TransitousClient.transitousURL)
    }
}

final class ShopSearchTests: XCTestCase {
    private func place(_ name: String, _ lat: Double, _ lon: Double) -> Place {
        Place(name: name, stopId: nil, parentId: nil, lat: lat, lon: lon, tz: "Europe/Berlin",
              scheduledArrival: nil, scheduledDeparture: nil, scheduledTrack: nil)
    }

    func testOperatorsWithASearchableShop() {
        XCTAssertEqual(ShopSearch.shop(for: "DB Fernverkehr AG"), .db)
        XCTAssertEqual(ShopSearch.shop(for: "Deutsche Bahn"), .db)
        XCTAssertEqual(ShopSearch.shop(for: "FlixBus"), .flix)
        XCTAssertEqual(ShopSearch.shop(for: "FlixTrain GmbH"), .flix)
        XCTAssertNil(ShopSearch.shop(for: "ÖBB-Personenverkehr AG"))
        XCTAssertNil(ShopSearch.shop(for: "Wiener Linien"))
    }

    func testDBSearchHasStartDestinationAndLocalDepartureTime() throws {
        // 2026-11-25 07:00 UTC = 08:00 in Munich.
        let departure = Date(timeIntervalSince1970: 1_795_590_000)
        let search = try XCTUnwrap(ShopSearch(operatorName: "DB Fernverkehr AG", from: place("München Hbf", 48.14, 11.56),
                                              to: place("Nürnberg Hbf", 49.45, 11.08), departure: departure))
        let url = try XCTUnwrap(search.dbURL).absoluteString
        XCTAssertTrue(url.hasPrefix("https://www.bahn.de/buchung/fahrplan/suche#sts=true&"), url)
        XCTAssertTrue(url.contains("so=M%C3%BCnchen%20Hbf"), url)
        XCTAssertTrue(url.contains("zo=N%C3%BCrnberg%20Hbf"), url)
        XCTAssertTrue(url.contains("soid=A%3D1%40O%3DM%C3%BCnchen%20Hbf%40"), url)
        XCTAssertTrue(url.contains("hd=2026-11-25T08:00:00"), url)
    }

    func testFlixSearchUsesCityIDsAndShopDate() throws {
        let departure = Date(timeIntervalSince1970: 1_795_590_000)
        let search = try XCTUnwrap(ShopSearch(operatorName: "FlixBus", from: place("Wien Erdberg (VIB)", 48.19, 16.41),
                                              to: place("Graz Hbf", 47.07, 15.42), departure: departure))
        XCTAssertNil(search.dbURL)
        let url = try XCTUnwrap(search.flixURL(fromCity: "a", toCity: "b"))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "shop.flixbus.com")
        XCTAssertEqual(items["departureCity"], "a")
        XCTAssertEqual(items["arrivalCity"], "b")
        XCTAssertEqual(items["rideDate"], "25.11.2026")
    }

    func testFlixCityIsTheNearestMatchWithin50Km() throws {
        XCTAssertEqual(FlixCities.queries(for: "Wien Erdberg (VIB)"), ["Wien Erdberg", "Wien"])
        XCTAssertEqual(FlixCities.queries(for: "Graz"), ["Graz"])
        let json = """
        [{"id":"far","name":"Wien","location":{"lat":52.5,"lon":13.4}},
         {"id":"vie","name":"Wien","location":{"lat":48.2,"lon":16.37}},
         {"id":"air","name":"Flughafen Wien","location":{"lat":48.11,"lon":16.56}}]
        """
        let cities = try JSONDecoder().decode([FlixCities.City].self, from: Data(json.utf8))
        XCTAssertEqual(FlixCities.nearest(cities, to: LatLon(lat: 48.19, lon: 16.41))?.id, "vie")
        XCTAssertNil(FlixCities.nearest(cities, to: LatLon(lat: 40.4, lon: -3.7)))
    }
}
