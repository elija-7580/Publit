import Foundation
import XCTest
@testable import Publit

final class TicketTextParserTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
    }

    func testRailTicketWithLabels() {
        let d = TicketTextParser.parse(lines: [
            "ÖBB", "Sparschiene", "Ticket-Nr.: 1234 5678 9012", "Von: Wien Hbf", "Nach: Salzburg Hbf",
            "Gültig am 14.10.2025", "2. Klasse", "Reisender: Max Mustermann", "Preis: € 19,90",
        ], calendar: calendar)
        XCTAssertEqual(d.operatorName, "ÖBB")
        XCTAssertEqual(d.title, "Sparschiene")
        XCTAssertEqual(d.category, .single)
        XCTAssertEqual(d.symbol, .train)
        XCTAssertEqual(d.origin, "Wien Hbf")
        XCTAssertEqual(d.destination, "Salzburg Hbf")
        XCTAssertEqual(d.validFrom, date(2025, 10, 14))
        XCTAssertEqual(d.validUntil, date(2025, 10, 14, 23, 59, 59))
        XCTAssertEqual(d.travelClass, "2")
        XCTAssertEqual(d.passenger, "Max Mustermann")
        XCTAssertEqual(d.price, "€ 19,90")
        XCTAssertEqual(d.reference, "1234 5678 9012")
    }

    func testMonthlyPassIgnoresBirthAndPurchaseDates() {
        let d = TicketTextParser.parse(lines: [
            "Deutschlandticket", "Gültigkeit: 01.10.2025 - 31.10.2025", "Name: Erika Musterfrau",
            "Geb.: 12.08.1964", "Kauf: 28.09.2025", "Ticket-ID: DT8K2LQ9",
        ], calendar: calendar)
        XCTAssertEqual(d.title, "Deutschlandticket")
        XCTAssertEqual(d.category, .subscription)
        XCTAssertEqual(d.validFrom, date(2025, 10, 1))
        XCTAssertEqual(d.validUntil, date(2025, 10, 31, 23, 59, 59))
        XCTAssertEqual(d.passenger, "Erika Musterfrau")
        XCTAssertEqual(d.reference, "DT8K2LQ9")
        XCTAssertNil(d.origin)
    }

    func testEnglishArrowRouteAndTextualDate() {
        let d = TicketTextParser.parse(lines: [
            "SNCF", "Paris Gare de Lyon → Lyon Part-Dieu", "Travel date 12 Nov 2025", "Departure 08:04",
            "2nd class", "Total 49.00 EUR", "Booking reference: QXRT7Z",
        ], calendar: calendar)
        XCTAssertEqual(d.operatorName, "SNCF")
        XCTAssertEqual(d.origin, "Paris Gare de Lyon")
        XCTAssertEqual(d.destination, "Lyon Part-Dieu")
        XCTAssertEqual(d.validFrom, date(2025, 11, 12))
        XCTAssertEqual(d.validUntil, date(2025, 11, 12, 23, 59, 59))
        XCTAssertEqual(d.travelClass, "2")
        XCTAssertEqual(d.price, "49.00 EUR")
        XCTAssertEqual(d.reference, "QXRT7Z")
    }

    func testLabelsOnTheirOwnLine() {
        let d = TicketTextParser.parse(lines: ["Gültig bis", "31.12.2025", "Von", "Graz Hbf", "Nach", "Wien Meidling"], calendar: calendar)
        XCTAssertNil(d.validFrom)
        XCTAssertEqual(d.validUntil, date(2025, 12, 31, 23, 59, 59))
        XCTAssertEqual(d.origin, "Graz Hbf")
        XCTAssertEqual(d.destination, "Wien Meidling")
    }

    func testRangeWithTimes() {
        let d = TicketTextParser.parse(lines: ["Tageskarte", "Gültig ab 14.10.2025 08:00 bis 15.10.2025 08:00"], calendar: calendar)
        XCTAssertEqual(d.category, .dayPass)
        XCTAssertEqual(d.validFrom, date(2025, 10, 14, 8, 0))
        XCTAssertEqual(d.validUntil, date(2025, 10, 15, 8, 0))
    }

    func testWholeMonth() {
        let d = TicketTextParser.parse(lines: ["Deutschlandticket", "Gültig im Oktober 2025"], calendar: calendar)
        XCTAssertEqual(d.validFrom, date(2025, 10, 1))
        XCTAssertEqual(d.validUntil, date(2025, 10, 31, 23, 59, 59))
    }

    func testStationNamesAreNotMonths() {
        let d = TicketTextParser.parse(lines: ["Marienplatz 2025", "Wien 2025"], calendar: calendar)
        XCTAssertNil(d.validFrom)
        XCTAssertNil(d.validUntil)
    }

    func testIssuerFromUICBarcode() {
        let code = TicketPass.Barcode(format: .aztec, payload: Data("#UT01118100001".utf8) + Data([0x00, 0xFF, 0x10]))
        XCTAssertTrue(code.isUIC)
        XCTAssertEqual(code.uicIssuerCode, "1181")
        let d = TicketTextParser.parse(lines: ["Fahrkarte"], barcodes: [code], calendar: calendar)
        XCTAssertEqual(d.operatorName, "ÖBB")
    }

    func testShortOperatorNamesNeedWholeWords() {
        XCTAssertNil(TicketTextParser.parse(lines: ["Hubbbs Café"], calendar: calendar).operatorName)
        XCTAssertNil(TicketTextParser.parse(lines: ["Total sbb"], calendar: calendar).operatorName)
        XCTAssertEqual(TicketTextParser.parse(lines: ["SBB CFF FFS"], calendar: calendar).operatorName, "SBB")
    }

    func testReturnTicketAndLongValidityBecomesPeriod() {
        XCTAssertEqual(TicketTextParser.parse(lines: ["Hinfahrt 12.10.2025", "Rückfahrt 14.10.2025"], calendar: calendar).category, .returnTrip)
        let d = TicketTextParser.parse(lines: ["Fahrkarte", "Gültig vom 01.10.2025 bis 07.10.2025"], calendar: calendar)
        XCTAssertEqual(d.category, .period)
    }
}

final class TicketPassModelTests: XCTestCase {
    func testValidityAndGrouping() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let valid = TicketPass(title: "A", validFrom: now - 3600, validUntil: now + 3600)
        let soon = TicketPass(title: "B", validFrom: now + 86400)
        let old = TicketPass(title: "C", validUntil: now - 60)
        let undated = TicketPass(title: "D")
        XCTAssertEqual(valid.validity(at: now), .valid(until: now + 3600))
        XCTAssertEqual(soon.validity(at: now), .upcoming(now + 86400))
        XCTAssertEqual(old.validity(at: now), .expired(now - 60))
        XCTAssertEqual(undated.validity(at: now), .unknown)
        let groups = PassGroup.grouped([old, undated, soon, valid], at: now)
        XCTAssertEqual(groups.map(\.group), [.valid, .upcoming, .undated, .expired])
    }

    func testBinaryCodeSurvivesWalletEncoding() {
        let bytes = Data((0...255).map { UInt8($0) })
        let code = TicketPass.Barcode(format: .aztec, payload: bytes)
        XCTAssertEqual(code.walletEncoding, "iso-8859-1")
        XCTAssertEqual(code.walletMessage.map { Data($0.unicodeScalars.map { UInt8($0.value) }) }, bytes)
    }

    func testStylesAreLegible() {
        for preset in PassStyle.presets {
            let bg = LineColors.RGB(hex: preset.style.background)!
            XCTAssertGreaterThanOrEqual(LineColors.contrast(LineColors.RGB(hex: preset.style.foreground)!, bg), 4.5, preset.name)
            XCTAssertGreaterThanOrEqual(LineColors.contrast(LineColors.RGB(hex: preset.style.label)!, bg), 4.5, preset.name)
        }
        for op in KnownOperators.all {
            let style = PassStyle(background: op.color)
            XCTAssertGreaterThanOrEqual(LineColors.contrast(LineColors.RGB(hex: style.label)!, LineColors.RGB(hex: style.background)!), 4.5, op.name)
        }
        XCTAssertEqual(PassStyle(background: "nonsense"), .standard)
        XCTAssertEqual(PassStyle.walletColor("FFC531"), "rgb(255, 197, 49)")
    }
}

final class WalletPassTests: XCTestCase {
    func testSHA1AndCRC32() {
        XCTAssertEqual(SHA1.hex(Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1.hex(Data()), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(SHA1.hex(Data(String(repeating: "a", count: 1000).utf8)), "291e9a6c66994949b57ba5e650361e98fc36b1ba")
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testZipHasLocalHeadersAndCentralDirectory() throws {
        let zip = ZipWriter.archive([.init(name: "pass.json", data: Data("{}".utf8)), .init(name: "icon.png", data: Data([1, 2, 3]))])
        let bytes = [UInt8](zip)
        func u32(_ i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(bytes[i + $1]) << ($1 * 8) } }
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        XCTAssertEqual(u32(0), 0x04034b50)
        let end = bytes.count - 22
        XCTAssertEqual(u32(end), 0x06054b50)
        XCTAssertEqual(u16(end + 10), 2)
        var offset = Int(u32(end + 16))
        var names: [String] = []
        for _ in 0..<2 {
            XCTAssertEqual(u32(offset), 0x02014b50)
            let nameLength = u16(offset + 28)
            names.append(String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self))
            let local = Int(u32(offset + 42))
            XCTAssertEqual(u32(local), 0x04034b50)
            offset += 46 + nameLength
        }
        XCTAssertEqual(names, ["pass.json", "icon.png"])
    }

    func testConfigRequiresHTTPSAndPassTypeIdentifier() {
        XCTAssertNil(WalletPassConfig(passTypeIdentifier: "pass.io.github.publit", teamIdentifier: "ABCDE12345", signerURL: "http://x.example"))
        XCTAssertNil(WalletPassConfig(passTypeIdentifier: "io.github.publit", teamIdentifier: "ABCDE12345", signerURL: "https://x.example"))
        XCTAssertNotNil(WalletPassConfig(passTypeIdentifier: "pass.io.github.publit", teamIdentifier: "ABCDE12345", signerURL: "https://x.example/sign"))
    }

    private struct FakeSigner: WalletPassSigning {
        func signature(passJSON: Data, manifest: Data) async throws -> Data { Data([0x30]) + Data(repeating: 1, count: 100) }
    }

    func testPassJSONAndManifest() async throws {
        let config = WalletPassConfig(passTypeIdentifier: "pass.io.github.publit", teamIdentifier: "ABCDE12345", signerURL: "https://x.example/sign")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let pass = TicketPass(title: "Sparschiene", operatorName: "ÖBB", symbol: .train, origin: "Wien Hbf", destination: "Salzburg Hbf",
                              travelClass: "2", reference: "1234", validUntil: calendar.date(from: DateComponents(year: 2025, month: 10, day: 14, hour: 23, minute: 59, second: 59)),
                              barcode: .init(format: .qr, message: "DEMO"), style: PassStyle(background: "D70015"))
        let json = try WalletPassBuilder.passJSON(for: pass, config: config, calendar: calendar)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(object["serialNumber"] as? String, pass.id)
        XCTAssertEqual(object["sharingProhibited"] as? Bool, true)
        let boarding = try XCTUnwrap(object["boardingPass"] as? [String: Any])
        XCTAssertEqual(boarding["transitType"] as? String, "PKTransitTypeTrain")
        XCTAssertEqual((boarding["primaryFields"] as? [[String: Any]])?.compactMap { $0["value"] as? String }, ["Wien Hbf", "Salzburg Hbf"])
        let header = try XCTUnwrap((boarding["headerFields"] as? [[String: Any]])?.first)
        XCTAssertEqual(header["timeStyle"] as? String, "PKDateStyleNone")
        XCTAssertEqual((object["barcodes"] as? [[String: Any]])?.first?["format"] as? String, "PKBarcodeFormatQR")
        XCTAssertNil(object["generic"])

        let data = try await WalletPassExport.make(pass: pass, images: ["icon.png": Data([9])], config: config,
                                                   signer: FakeSigner(), calendar: calendar)
        XCTAssertEqual([UInt8](data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let manifest = try WalletPassBuilder.manifest(["pass.json": json, "icon.png": Data([9])])
        let hashes = try XCTUnwrap(JSONSerialization.jsonObject(with: manifest) as? [String: String])
        XCTAssertEqual(hashes["pass.json"], SHA1.hex(json))

        do {
            _ = try await WalletPassExport.make(pass: pass, images: [:], config: config, signer: FakeSigner())
            XCTFail("needs an icon")
        } catch { XCTAssertEqual(error as? WalletPassError, .missingIcon) }
    }

    func testPassWithoutRouteUsesGenericStyle() throws {
        let config = WalletPassConfig(passTypeIdentifier: "pass.io.github.publit", teamIdentifier: "ABCDE12345", signerURL: "https://x.example/sign")!
        let built = try WalletPassBuilder.pass(for: TicketPass(title: "Deutschlandticket", category: .subscription), config: config)
        XCTAssertNil(built.boardingPass)
        XCTAssertEqual(built.generic?.primaryFields.first?.value, "Deutschlandticket")
    }
}

@MainActor
final class PassStoreTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("passes-\(UUID().uuidString)", isDirectory: true)
    }

    func testAddUpdateRemoveWithDocument() async throws {
        let dir = directory()
        let store = PassStore(directory: dir)
        let saved = try await store.add(TicketPass(title: "Demo"), document: Data("%PDF-1.4".utf8), kind: .pdf, page: 1)
        let url = try XCTUnwrap(store.documentURL(saved))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(saved.document?.page, 1)
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".pdf"))

        var edited = saved
        edited.title = "Edited"
        store.update(edited, now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(store.pass(saved.id)?.title, "Edited")
        JSONPersistence.flush()
        XCTAssertEqual(PassStore(directory: dir).pass(saved.id)?.title, "Edited")

        store.remove(saved.id)
        XCTAssertNil(store.pass(saved.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRejectsHugeDocuments() async {
        let store = PassStore(directory: directory())
        do {
            _ = try await store.add(TicketPass(), document: Data(count: PassStore.maxDocumentBytes + 1), kind: .image)
            XCTFail("too large")
        } catch { XCTAssertEqual(error as? PassStore.Failure, .documentTooLarge) }
        XCTAssertTrue(store.passes.isEmpty)
    }

    func testPassesForTrip() async {
        let store = PassStore(directory: directory())
        let now = Date()
        store.insert(TicketPass(title: "Own", category: .single, tripId: "t1"))
        store.insert(TicketPass(title: "Month", category: .period, validFrom: now - 86400, validUntil: now + 86400))
        store.insert(TicketPass(title: "Old month", category: .period, validUntil: now - 86400))
        store.insert(TicketPass(title: "Other trip", category: .single, tripId: "t2"))
        XCTAssertEqual(store.passes(forTrip: "t1", at: now).map(\.title), ["Own", "Month"])
    }

    func testEveryTicketAddedForATripShows() async {
        let store = PassStore(directory: directory())
        let now = Date()
        store.insert(TicketPass(title: "Adult", category: .single, tripId: "t1", createdAt: now - 60))
        store.insert(TicketPass(title: "Child", category: .single, tripId: "t1", createdAt: now - 30))
        store.insert(TicketPass(title: "Bike", category: .other, tripId: "t1", createdAt: now))
        store.insert(TicketPass(title: "Day", category: .dayPass, validUntil: now - 86400, tripId: "t1", createdAt: now))
        store.insert(TicketPass(title: "Wallet single", category: .single, validFrom: now - 3600, validUntil: now + 3600))
        store.insert(TicketPass(title: "Undated", category: .single))
        store.insert(TicketPass(title: "Other trip", category: .single, validUntil: now + 3600, tripId: "t2"))
        XCTAssertEqual(store.passes(forTrip: "t1", at: now).map(\.title), ["Adult", "Child", "Bike", "Day", "Wallet single"])
        XCTAssertEqual(store.passes(forTrip: nil, at: now).map(\.title), ["Wallet single"])
    }

    func testImportsLegacyTicketsOnce() async throws {
        let dir = directory()
        let images = dir.appendingPathComponent("tickets", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: images.appendingPathComponent("a.img"))
        let legacy = Ticket(id: "a", name: "KlimaTicket", kind: .pass, imageFile: "a.img", appLink: "https://example.com",
                            validUntil: nil, tripId: nil, addedAt: Date(timeIntervalSince1970: 0))
        let store = PassStore(directory: dir)
        XCTAssertEqual(store.importLegacy([legacy], imageDirectory: images), 1)
        XCTAssertEqual(store.importLegacy([legacy], imageDirectory: images), 0)
        let pass = try XCTUnwrap(store.passes.first)
        XCTAssertEqual(pass.title, "KlimaTicket")
        XCTAssertEqual(pass.category, .period)
        XCTAssertEqual(pass.document?.kind, .image)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.documentURL(pass))), Data([1, 2, 3]))
    }
}
