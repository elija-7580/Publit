import SwiftUI
import UIKit

/// A season ticket shows its real code; single rides remain compact rows.
struct WalletPassTile: View {
    let pass: TicketPass
    let now: Date
    var source: BarcodeSource? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                if let op = pass.operatorName {
                    Text(verbatim: op.uppercased()).font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: pass.style.label) ?? .white)
                }
                Text(verbatim: pass.displayTitle).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let end = pass.validUntil {
                    Text(verbatim: L10n.t("Valid until") + " " + PassFormat.date(end, end: true)).font(.caption)
                } else {
                    Text(verbatim: pass.category.title).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let code = pass.barcode, code.format.isSquare {
                BarcodeView(code: code, source: source).frame(width: 70, height: 70)
                    .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 13))
            } else {
                Image(systemName: pass.symbol.systemImage).font(.title).frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .foregroundStyle(Color(hex: pass.style.foreground) ?? .white)
        .background(Color(hex: pass.style.background) ?? .black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(pass.isArchived(at: now) ? 0.7 : 1)
    }
}

struct WalletTicketRow: View {
    let pass: TicketPass
    var logo: UIImage? = nil
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let logo {
                    Image(uiImage: logo).resizable().scaledToFit().padding(4)
                        .background(.white, in: RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: pass.symbol.systemImage).font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.onInk).background(Color.ink, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .frame(width: 34, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: pass.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(verbatim: [pass.validFrom.map { PassFormat.date($0, end: false) }, pass.passenger ?? pass.operatorName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 13).frame(minHeight: 64).contentShape(Rectangle())
    }
}
