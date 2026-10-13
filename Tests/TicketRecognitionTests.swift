#if canImport(UIKit) && canImport(Vision)
import XCTest
@testable import Publit

final class TicketRecognitionTests: XCTestCase {
    @MainActor func testEmbeddedPDFTextProducesTicketDates() async throws {
        let data = SharedTicketSamples.pdf([SharedTicketSamples.ticketLines])
        let scan = try await TicketRecognizer.scan(pdf: data, page: 0)
        let draft = TicketTextParser.parse(lines: scan.lines, barcodes: scan.barcodes, strictValidity: true)
        XCTAssertEqual(draft.title, "Sparschiene")
        XCTAssertEqual(draft.origin, "Wien Hbf")
        XCTAssertNotNil(draft.validUntil)
        XCTAssertTrue(TicketImportPolicy.canAddAutomatically(draft, barcodes: scan.barcodes))
    }

    @MainActor func testImageIsRecognizedLocally() async throws {
        let scan: TicketScan
        do {
            scan = try await TicketRecognizer.scan(imageData: SharedTicketSamples.image())
        } catch {
            // Pure images need Vision OCR/barcodes; some simulator hosts cannot create an inference context.
            throw XCTSkip("Vision unavailable on this host: \(error.localizedDescription)")
        }
        let draft = TicketTextParser.parse(lines: scan.lines, barcodes: scan.barcodes, strictValidity: true)
        XCTAssertEqual(draft.title, "Sparschiene")
        XCTAssertTrue(TicketImportPolicy.canAddAutomatically(draft, barcodes: scan.barcodes))
    }

    @MainActor func testUniquePageAndMultipleTicketAmbiguity() async throws {
        let ticket = SharedTicketSamples.ticketLines
        let unique = SharedTicketSamples.pdf([["Information", "Keep your original", "No ticket on this page"], ticket])
        let found = try await TicketRecognizer.uniqueTicket(pdf: unique, count: 2)
        XCTAssertEqual(found?.page, 1)
        let ambiguous = try await TicketRecognizer.uniqueTicket(pdf: SharedTicketSamples.pdf([ticket, ticket]), count: 2)
        XCTAssertNil(ambiguous)
        let long = try await TicketRecognizer.uniqueTicket(pdf: unique, count: TicketImportPolicy.maxAutomaticPages + 1)
        XCTAssertNil(long, "bounded analysis must fall back to page choice")
    }

    func testMalformedDataFailsWithoutSaving() async {
        do { _ = try await TicketRecognizer.scan(pdf: Data("not a PDF".utf8), page: 0); XCTFail("read invalid file") } catch {}
        do { _ = try await TicketRecognizer.scan(imageData: Data()); XCTFail("read invalid image") } catch {}
    }
}
#endif
