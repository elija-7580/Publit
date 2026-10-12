#if canImport(Vision) && canImport(UIKit)
import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

/// What one page of a ticket contains, read on the device. Nothing is uploaded.
struct TicketScan: @unchecked Sendable {
    var lines: [String]
    var barcodes: [TicketPass.Barcode]
    /// The most prominent colour of the page, offered as "From ticket".
    var suggestedColor: String?
}

enum TicketRecognizer {
    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? { L10n.t("This file could not be read.") }
    }

    static func pageCount(pdf data: Data) -> Int { PDFDocument(data: data)?.pageCount ?? 0 }

    /// A PDF page as an image, sharp enough for small print and dense codes.
    static func renderPage(pdf data: Data, page: Int, maxPixels: CGFloat = 2600) -> UIImage? {
        guard let document = PDFDocument(data: data), let p = document.page(at: page) else { return nil }
        let box = p.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(maxPixels / max(box.width, box.height), 6)
        return p.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
    }

    /// Text embedded in the PDF is exact, so it replaces OCR when the page has enough of it.
    static func scan(pdf data: Data, page: Int) async throws -> TicketScan {
        let (image, text) = try await Task.detached(priority: .userInitiated) { () throws -> (CGImage, String?) in
            guard let cg = TicketRecognizer.renderPage(pdf: data, page: page)?.cgImage else { throw Failure.unreadable }
            return (cg, PDFDocument(data: data)?.page(at: page)?.string)
        }.value
        var result = try await scan(image: image)
        let embedded = (text ?? "").components(separatedBy: .newlines).map(TicketTextParser.clean).filter { !$0.isEmpty }
        if embedded.count >= 3 { result.lines = embedded }
        return result
    }

    static func scan(imageData data: Data) async throws -> TicketScan {
        let image = try await Task.detached(priority: .userInitiated) { () throws -> CGImage in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3200,
                  ] as CFDictionary) else { throw Failure.unreadable }
            return cg
        }.value
        return try await scan(image: image)
    }

    static func scan(image: CGImage) async throws -> TicketScan {
        try await Task.detached(priority: .userInitiated) { () throws -> TicketScan in
            let trace = PerformanceTrace.begin("Recognise ticket")
            defer { PerformanceTrace.end(trace, "Recognise ticket") }
            let codes = VNDetectBarcodesRequest()
            codes.symbologies = [.qr, .aztec, .pdf417, .code128]
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            // Names, numbers and codes: language correction changes more than it fixes.
            text.usesLanguageCorrection = false
            text.automaticallyDetectsLanguage = true
            if let supported = try? text.supportedRecognitionLanguages() {
                let wanted = ["de-DE", "en-US", "fr-FR", "it-IT", "es-ES", "pt-BR", "nl-NL"].filter(supported.contains)
                if !wanted.isEmpty { text.recognitionLanguages = wanted }
            }
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([codes, text])
            var seen = Set<String>()
            let barcodes = (codes.results ?? []).compactMap(TicketRecognizer.barcode).filter { seen.insert($0.dedupeKey).inserted }
            return TicketScan(lines: TicketRecognizer.lines(text.results ?? []), barcodes: barcodes,
                              suggestedColor: TicketRecognizer.dominantColor(image))
        }.value
    }

    /// Vision returns text pieces; pieces on the same row become one line ("Von:" + "Wien Hbf").
    static func lines(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let pieces = observations.compactMap { o -> (box: CGRect, text: String)? in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            return (o.boundingBox, text)
        }.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(box: CGRect, text: String)]] = []
        for piece in pieces {
            if let last = rows.last?.last, abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    private static func barcode(_ o: VNBarcodeObservation) -> TicketPass.Barcode? {
        let format: TicketPass.Barcode.Format
        switch o.symbology {
        case .qr: format = .qr
        case .aztec: format = .aztec
        case .pdf417: format = .pdf417
        case .code128: format = .code128
        default: return nil
        }
        let descriptor = o.barcodeDescriptor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        let message = o.payloadStringValue
        // Raw bytes only when the text does not carry them exactly (binary rail ticket codes).
        var payload = o.payloadData
        if let message, let bytes = payload, Data(message.utf8) == bytes { payload = nil }
        guard message != nil || payload != nil || descriptor != nil else { return nil }
        return TicketPass.Barcode(format: format, message: payload == nil ? message : nil, payload: payload, descriptor: descriptor)
    }

    /// Average of the clearly coloured pixels; nil for black-and-white tickets.
    static func dominantColor(_ image: CGImage) -> String? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var (r, g, b, weight) = (0.0, 0.0, 0.0, 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let (pr, pg, pb) = (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            guard saturation > 0.35, maxC > 0.2 else { continue }
            r += pr * saturation; g += pg * saturation; b += pb * saturation; weight += saturation
        }
        guard weight > Double(side * side) * 0.03 else { return nil }
        return PassStyle.hex(LineColors.RGBValues(r: r / weight, g: g / weight, b: b / weight))
    }
}
#endif
