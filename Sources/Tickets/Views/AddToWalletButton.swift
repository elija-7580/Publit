import PassKit
import SwiftUI
import UIKit

/// Apple's "Add to Apple Wallet" button. Builds and signs the pass only when tapped.
/// Shown only when Wallet export is configured (WalletPassConfig) and the code can be exported.
struct AddToWalletButton: View {
    let pass: TicketPass
    @State private var walletPass: IdentifiedPass?
    @State private var working = false
    @State private var error: String?

    struct IdentifiedPass: Identifiable {
        let pass: PKPass
        var id: String { pass.serialNumber }
    }

    var body: some View {
        WalletButton { Task { await export() } }
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .opacity(working ? 0.5 : 1)
            .disabled(working || !PKAddPassesViewController.canAddPasses())
            .overlay { if working { ProgressView() } }
            .accessibilityIdentifier("addToWallet")
            .sheet(item: $walletPass) { item in AddPassesSheet(pass: item.pass).ignoresSafeArea() }
            .alert(L10n.t("The Wallet pass could not be created."), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: error ?? "")
            }
    }

    private func export() async {
        guard let config = WalletPassConfig.current, !working else { return }
        working = true
        defer { working = false }
        do {
            let images = WalletPassImages.render(pass)
            let data = try await WalletPassExport.make(pass: pass, images: images, config: config,
                                                       signer: RemoteWalletPassSigner(endpoint: config.signerURL))
            walletPass = IdentifiedPass(pass: try PKPass(data: data))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct WalletButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) { context.coordinator.action = action }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

private struct AddPassesSheet: UIViewControllerRepresentable {
    let pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

/// Pass images: the icon (lock screen and notifications) in the pass colours.
enum WalletPassImages {
    static func render(_ pass: TicketPass) -> [String: Data] {
        var out: [String: Data] = [:]
        for (name, side) in [("icon.png", 29.0), ("icon@2x.png", 58.0), ("icon@3x.png", 87.0)] {
            out[name] = icon(pass, side: side)
        }
        return out
    }

    private static func icon(_ pass: TicketPass, side: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            let bg = LineColors.RGB(hex: pass.style.background) ?? LineColors.black
            let fg = LineColors.RGB(hex: pass.style.foreground) ?? LineColors.white
            UIColor(red: bg.r, green: bg.g, blue: bg.b, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: side * 0.5, weight: .semibold)
            if let symbol = UIImage(systemName: pass.symbol.systemImage, withConfiguration: config)?
                .withTintColor(UIColor(red: fg.r, green: fg.g, blue: fg.b, alpha: 1), renderingMode: .alwaysOriginal) {
                let s = symbol.size
                symbol.draw(in: CGRect(x: (side - s.width) / 2, y: (side - s.height) / 2, width: s.width, height: s.height))
            }
        }
    }
}
