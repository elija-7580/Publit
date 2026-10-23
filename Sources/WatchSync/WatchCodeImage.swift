import UIKit

/// The picture of a ticket's code for the watch screen: black on a white plate as wide as the screen,
/// every module a whole number of pixels. CoreImage is not on watchOS, so the iPhone draws it.
enum WatchCodeImage {
    /// PNG data of the plate, `width` pixels wide. Nil when the code cannot be drawn (and there is no original to cut it from).
    static func png(for code: TicketPass.Barcode, source: BarcodeSource?, width: Int) -> Data? {
        let w = CGFloat(WatchCodeFile.clamped(width))
        let margin = max(12, (w * 0.05).rounded())
        let room = w - 2 * margin
        guard let rendered = BarcodeRenderer.render(code, fitting: CGSize(width: room, height: room), scale: 1, source: source) else {
            return nil
        }
        let image = rendered.image
        var drawWidth = image.size.width
        var drawHeight = image.size.height
        guard drawWidth > 0, drawHeight > 0 else { return nil }
        if !rendered.exact {
            // A cut-out of the original page: scaled to fit, smoothly.
            let k = min(room / drawWidth, room / drawHeight)
            drawWidth = (drawWidth * k).rounded(.down)
            drawHeight = (drawHeight * k).rounded(.down)
        }
        let height = (drawHeight + 2 * margin).rounded(.up)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: height), format: format)
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: w, height: height))
            context.cgContext.interpolationQuality = rendered.exact ? .none : .high
            image.draw(in: CGRect(x: ((w - drawWidth) / 2).rounded(), y: margin, width: drawWidth, height: drawHeight))
        }
    }
}
