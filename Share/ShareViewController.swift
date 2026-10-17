import UIKit
import UniformTypeIdentifiers

/// "Publit" in the share sheet of Google Maps, Apple Maps and other apps: reads the shared link
/// or text (`MapLink`), follows a short link once, and opens Publit with routes to that place.
final class ShareViewController: UIViewController {
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = L10n.t("Opening in Publit…")
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textAlignment = .center
        let close = UIButton(type: .system, primaryAction: UIAction(title: L10n.t("Done")) { [weak self] _ in self?.finish() })
        let stack = UIStackView(arrangedSubviews: [spinner, status, close])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        spinner.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { @MainActor in await handle() }
    }

    private func handle() async {
        let text = await sharedText()
        guard let link = text.flatMap(MapLink.parse(text:)) else { return fail() }
        guard let place = await MapLink.resolve(link) ?? (link.name != nil ? MapLink(name: link.name) : nil),
              let url = place.appURL else { return fail() }
        if openApp(url) { finish() } else { fail() }
    }

    /// Shared URLs and text, joined: Google Maps sends the place name and its link.
    private func sharedText() async -> String? {
        var parts: [String] = []
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier),
               let url = (item as? URL) ?? (item as? String).flatMap(URL.init(string:)) {
                parts.append(url.absoluteString)
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let item = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                      let s = item as? String {
                parts.insert(s, at: 0)
            }
        }
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            if let s = item.attributedContentText?.string, !s.isEmpty { parts.insert(s, at: 0) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Share extensions cannot open other apps directly; the app object in the responder chain can.
    private func openApp(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = r.next
        }
        return false
    }

    private func fail() {
        spinner.stopAnimating()
        status.text = L10n.t("No place found in what was shared. Share a place or a pin from a map app.")
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
