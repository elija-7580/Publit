import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Add a ticket: choose a PDF, photo or screenshot (or scan paper), pick the page,
/// let Publit read it on the device, then check the result.
struct PassImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .choose
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @State private var scanning = false

    enum Stage {
        case choose
        case reading
        case pages(Data, count: Int)
        case review(PassEditorView.Mode)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose: chooser
                case .reading:
                    ProgressView(L10n.t("Reading ticket…")).controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .pages(let data, let count): PagePicker(data: data, count: count) { page in
                    Task { await read(data, pdf: true, page: page) }
                }
                case .review(let mode): PassEditorView(mode: mode) { dismiss() }
                case .failed(let message):
                    ContentUnavailableView {
                        Label(L10n.t("This file could not be read."), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(verbatim: message)
                    } actions: {
                        Button(L10n.t("Try another file")) { stage = .choose }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                // The check screen has its own Cancel and Save.
                ToolbarItem(placement: .cancellationAction) {
                    if showsCancel { Button("Cancel") { dismiss() } }
                }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            Task { await open(url) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                stage = .reading
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await read(data, pdf: false, page: 0)
                } else {
                    stage = .failed(L10n.t("The photo could not be loaded."))
                }
                photo = nil
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { image in
                scanning = false
                guard let image, let data = image.jpegData(compressionQuality: 0.9) else { return }
                Task { await read(data, pdf: false, page: 0) }
            }
            .ignoresSafeArea()
        }
    }

    private var showsCancel: Bool {
        if case .review = stage { return false }
        return true
    }

    private var chooser: some View {
        List {
            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(L10n.t("Photo or screenshot"), systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("importPhoto")
                Button { choosingFile = true } label: {
                    Label(L10n.t("PDF or image file"), systemImage: "doc")
                }
                .accessibilityIdentifier("importFile")
                if VNDocumentCameraViewController.isSupported {
                    Button { scanning = true } label: {
                        Label(L10n.t("Scan a paper ticket"), systemImage: "doc.viewfinder")
                    }
                }
            } footer: {
                Text("Publit reads the ticket on your iPhone. Nothing is uploaded. Codes that change every few seconds only work in the operator's app.")
            }
        }
        .navigationTitle(L10n.t("Add ticket"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func open(_ url: URL) async {
        stage = .reading
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
        let loaded = await Task.detached(priority: .userInitiated) { () -> Data? in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= PassStore.maxDocumentBytes else { return nil }
            return try? Data(contentsOf: url)
        }.value
        guard let data = loaded else {
            stage = .failed(L10n.t("This file is too large for a ticket."))
            return
        }
        guard isPDF else { await read(data, pdf: false, page: 0); return }
        let count = TicketRecognizer.pageCount(pdf: data)
        if count > 1 { stage = .pages(data, count: count) } else { await read(data, pdf: true, page: 0) }
    }

    private func read(_ data: Data, pdf: Bool, page: Int) async {
        stage = .reading
        do {
            let scan = pdf ? try await TicketRecognizer.scan(pdf: data, page: page) : try await TicketRecognizer.scan(imageData: data)
            let draft = TicketTextParser.parse(lines: scan.lines, barcodes: scan.barcodes)
            var pass = TicketPass(draft: draft, barcode: scan.barcodes.first)
            if PassStyle.suggested(forOperator: draft.operatorName) == nil, let color = scan.suggestedColor {
                pass.style = PassStyle(background: color)
            }
            stage = .review(.new(pass, document: data, kind: pdf ? .pdf : .image, page: page,
                                 codes: scan.barcodes, colorFromTicket: scan.suggestedColor))
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

/// Multi-page PDFs (e.g. outward and return ticket): choose the page with the ticket.
private struct PagePicker: View {
    let data: Data
    let count: Int
    let choose: (Int) -> Void
    @State private var thumbnails: [Int: UIImage] = [:]

    var body: some View {
        ScrollView {
            Text("Which page is the ticket?").font(.headline).padding(.top)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(0..<min(count, 20), id: \.self) { page in
                    Button { choose(page) } label: {
                        VStack {
                            Group {
                                if let image = thumbnails[page] { Image(uiImage: image).resizable().scaledToFit() }
                                else { ProgressView().frame(height: 180) }
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                            Text(verbatim: L10n.f("Page %lld", page + 1)).font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .task {
                        let data = data
                        let image = await Task.detached(priority: .userInitiated) {
                            TicketRecognizer.renderPage(pdf: data, page: page, maxPixels: 420)
                        }.value
                        thumbnails[page] = image
                    }
                }
            }
            .padding()
        }
        .navigationTitle(L10n.t("Choose page"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// VisionKit's document camera: edge detection and perspective correction for paper tickets.
private struct DocumentScanner: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }
}
