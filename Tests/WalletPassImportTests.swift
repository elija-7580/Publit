// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Tickets from Apple Wallet passes (#20) and text read from pictures inside PDFs (#5).
final class WalletPassImportTests: XCTestCase {
    private let boardingPass = """
    {"formatVersion":1,"passTypeIdentifier":"pass.example","serialNumber":"ABC123","teamIdentifier":"X",
     "organizationName":"ÖBB","description":"Ticket Wien – Salzburg","backgroundColor":"rgb(215, 0, 21)",
     "relevantDate":"2026-12-01T08:00:00+01:00","expirationDate":"2026-12-02T03:00:00+01:00",
     "barcodes":[{"format":"PKBarcodeFormatAztec","message":"#UT01HELLO","messageEncoding":"iso-8859-1"}],
     "boardingPass":{"transitType":"PKTransitTypeTrain",
       "primaryFields":[{"key":"from","label":"Wien Hbf","value":"WIE"},{"key":"to","label":"Salzburg Hbf","value":"SBG"}],
       "auxiliaryFields":[{"key":"passenger","label":"Passenger","value":"Alex Example"},{"key":"class","label":"Class","value":"2. Klasse"}],
       "backFields":[{"key":"terms","label":"Conditions","value":"Valid on the day shown."}]}}
    """

    func testBoardingPassBecomesATicketWithItsCode() throws {
        let r = try WalletPassImport.read(passJSON: Data(boardingPass.utf8))
        XCTAssertEqual(r.pass.operatorName, "ÖBB")
        XCTAssertEqual(r.pass.origin, "Wien Hbf")
        XCTAssertEqual(r.pass.destination, "Salzburg Hbf")
        XCTAssertEqual(r.pass.symbol, .train)
        XCTAssertEqual(r.pass.passenger, "Alex Example")
        XCTAssertEqual(r.pass.travelClass, "2")
        XCTAssertEqual(r.pass.barcode?.format, .aztec)
        XCTAssertEqual(r.pass.barcode?.message, "#UT01HELLO")
        XCTAssertNotNil(r.pass.validFrom)
        XCTAssertNotNil(r.pass.validUntil)
        XCTAssertEqual(r.color, "D70015")
        XCTAssertTrue(r.pass.notes?.contains("Conditions: Valid on the day shown.") == true)
    }

    func testPkpassFileIsReadFromItsArchive() throws {
        let zip = ZipWriter.archive([ZipWriter.Entry(name: "icon.png", data: Data([1, 2, 3])),
                                     ZipWriter.Entry(name: "pass.json", data: Data(boardingPass.utf8))])
        XCTAssertEqual(try ZipReader.entries(zip).map(\.name), ["icon.png", "pass.json"])
        XCTAssertEqual(try ZipReader.file("icon.png", in: zip), Data([1, 2, 3]))
        let r = try WalletPassImport.read(pkpass: zip)
        XCTAssertEqual(r.pass.destination, "Salzburg Hbf")
        XCTAssertThrowsError(try WalletPassImport.read(pkpass: Data("not a zip".utf8)))
        XCTAssertThrowsError(try WalletPassImport.read(pkpass: ZipWriter.archive([ZipWriter.Entry(name: "x.txt", data: Data())])))
    }

    func testBinaryCodesKeepTheirBytes() throws {
        let json = ##"{"organizationName":"DB","barcode":{"format":"PKBarcodeFormatAztec","message":"#UT\u0001ÿ","messageEncoding":"iso-8859-1"},"generic":{}}"##
        let r = try WalletPassImport.read(passJSON: Data(json.utf8))
        XCTAssertEqual(r.pass.barcode?.payload, Data([0x23, 0x55, 0x54, 0x01, 0xFF]))
    }

    func testColours() {
        XCTAssertEqual(WalletPassImport.hex("rgb(0, 102, 214)"), "0066D6")
        XCTAssertEqual(WalletPassImport.hex("#ffc531"), "FFC531")
        XCTAssertNil(WalletPassImport.hex("rgb(300, 0, 0)"))
    }

    func testRecognisedTextFillsWhatThePDFHasOnlyAsPictures() {
        let embedded = [TicketTextPiece(id: 0, text: "Wien Hbf", rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05))]
        let recognized = [TicketTextPiece(id: 0, text: "Wien Hbf", rect: CGRect(x: 0.11, y: 0.1, width: 0.28, height: 0.05)),
                          TicketTextPiece(id: 1, text: "Alex Example", rect: CGRect(x: 0.1, y: 0.3, width: 0.3, height: 0.05))]
        let merged = TicketTextPiece.merging(embedded: embedded, recognized: recognized)
        XCTAssertEqual(merged.map(\.text), ["Wien Hbf", "Alex Example"])
        XCTAssertEqual(merged.map(\.id), [0, 1])
        XCTAssertEqual(TicketTextPiece.mergedLines(embedded: ["Von Wien Hbf", "Nach Salzburg"], recognized: ["Von Wien Hbf", "Gültig bis 02.12.2026", "x"]),
                       ["Von Wien Hbf", "Nach Salzburg", "Gültig bis 02.12.2026"])
    }
}
