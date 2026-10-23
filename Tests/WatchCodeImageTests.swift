#if canImport(UIKit)
import CoreImage
import UIKit
import XCTest
@testable import Publit

/// The pictures of ticket codes for the Apple Watch (drawn on the iPhone, sent to the watch).
final class WatchCodeImageTests: XCTestCase {
    private func read(_ png: Data) -> String? {
        guard let image = CIImage(data: png),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return nil }
        return (detector.features(in: image).first as? CIQRCodeFeature)?.messageString
    }

    func testQRCodeComesOnAWhitePlateAsWideAsTheWatchAsksAndCanBeRead() throws {
        let code = TicketPass.Barcode(format: .qr, message: "PUBLIT-WATCH-0001")
        let png = try XCTUnwrap(WatchCodeImage.png(for: code, source: nil, width: 352))
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size.width * image.scale, 352)
        XCTAssertGreaterThanOrEqual(image.size.height * image.scale, 300)
        XCTAssertLessThanOrEqual(image.size.height * image.scale, 360)
        XCTAssertEqual(read(png), "PUBLIT-WATCH-0001")
    }

    func testTheWidthStaysInTheRangeTheWatchCanShow() throws {
        let code = TicketPass.Barcode(format: .qr, message: "PUBLIT-WATCH-0002")
        let narrow = try XCTUnwrap(UIImage(data: try XCTUnwrap(WatchCodeImage.png(for: code, source: nil, width: 20))))
        XCTAssertEqual(narrow.size.width * narrow.scale, CGFloat(WatchCodeFile.pixelRange.lowerBound))
        let wide = try XCTUnwrap(UIImage(data: try XCTUnwrap(WatchCodeImage.png(for: code, source: nil, width: 5000))))
        XCTAssertEqual(wide.size.width * wide.scale, CGFloat(WatchCodeFile.pixelRange.upperBound))
    }

    func testACodeThatCannotBeDrawnAgainHasNoPictureWithoutTheOriginal() {
        let code = TicketPass.Barcode(format: .ean13, message: "4006381333931")
        // EAN-13 is cut out of the original page; without one there is nothing to draw.
        XCTAssertNil(WatchCodeImage.png(for: code, source: nil, width: 352))
    }
}
#endif
