#if canImport(UIKit)
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Draws a stored code again: black on white, every module a whole number of pixels, so scanners read it.
enum BarcodeRenderer {
    private static let context = CIContext()

    static func ciImage(_ code: TicketPass.Barcode) -> CIImage? {
        let classes: [AnyClass] = [CIBarcodeDescriptor.self, CIQRCodeDescriptor.self, CIAztecCodeDescriptor.self,
                                   CIPDF417CodeDescriptor.self, CIDataMatrixCodeDescriptor.self, NSData.self, NSNumber.self]
        if let archived = code.descriptor,
           let descriptor = (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: archived)) as? CIBarcodeDescriptor {
            let filter = CIFilter.barcodeGenerator()
            filter.barcodeDescriptor = descriptor
            if let out = filter.outputImage { return out }
        }
        guard let bytes = code.bytes else { return nil }
        switch code.format {
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = bytes
            f.correctionLevel = "M"
            return f.outputImage
        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = bytes
            f.correctionLevel = 23
            return f.outputImage
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = bytes
            return f.outputImage
        case .code128:
            let f = CIFilter.code128BarcodeGenerator()
            f.message = bytes
            f.quietSpace = 0
            return f.outputImage
        }
    }

    static func image(_ code: TicketPass.Barcode, targetWidth: CGFloat = 900) -> UIImage? {
        guard let image = ciImage(code), image.extent.width > 0 else { return nil }
        let scale = max(1, floor(targetWidth / image.extent.width))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif
