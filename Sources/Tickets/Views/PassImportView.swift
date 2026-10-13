import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Add a ticket: choose a PDF, photo or screenshot (or scan paper), pick the page,
/// let Publit read it on the device, then check the result.
struct PassImportView: View {
    /// A single ticket added from a trip belongs to that trip.
    var tripId: String? = nil
    var sharedURL: URL? = nil
    @Environment(PassStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .choose
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @State private var choosingPhoto = false
    @State private var scanning = false
    @State private var readingTask: Task<Void, Never>?

    enum Stage {
        case choose
        case reading
        case pages(Data, count: Int)
        case review(PassEditorView.Mode)
        case failed(String)
        case added(TicketPass, duplicate: Bool)
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
                    readingTask?.cancel()
                    readingTask = Task { await read(data, pdf: true, page: page) }
                }
                case .review(let mode): PassEditorView(mode: mode) { dismiss() }
                case .added(let pass, let duplicate): added(pass, duplicate: duplicate)
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
                    if showsCancel { Button("Cancel") { readingTask?.cancel(); dismiss() } }
                }
            }
        }
        .onDisappear {
            if !scanning && !choosingFile && !choosingPhoto { readingTask?.cancel() }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .task { if let sharedURL { await open(sharedURL) } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            readingTask?.cancel()
            readingTask = Task { await open(url) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            readingTask?.cancel()
            readingTask = Task {
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
                readingTask?.cancel()
                readingTask = Task { await read(data, pdf: false, page: 0) }
            }
            .ignoresSafeArea()
        }
    }

    private var showsCancel: Bool {
        if case .review = stage { return false }
        if case .added = stage { return false }
        return true
    }

    private var chooser: some View {
        List {
            Section {
                Button { choosingPhoto = true } label: {
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
        do {
            let type = UTType(filenameExtension: url.pathExtension)
            guard type?.conforms(to: .pdf) == true || type?.conforms(to: .image) == true else {
                throw TicketRecognizer.Failure.unreadable
            }
            let isPDF = type?.conforms(to: .pdf) == true
            let data = try await Task.detached(priority: .userInitiated) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= PassStore.maxDocumentBytes else { throw PassStore.Failure.documentTooLarge }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: PassStore.maxDocumentBytes + 1) ?? Data()
                guard bytes.count <= PassStore.maxDocumentBytes else { throw PassStore.Failure.documentTooLarge }
                guard !bytes.isEmpty else { throw TicketRecognizer.Failure.unreadable }
                return bytes
            }.value
            try Task.checkCancellation()
            guard isPDF else { await read(data, pdf: false, page: 0); return }
            let count = await Task.detached(priority: .userInitiated) { TicketRecognizer.pageCount(pdf: data) }.value
            if count > 1 {
                if sharedURL != nil, let candidate = try await TicketRecognizer.uniqueTicket(pdf: data, count: count) {
                    await accept(candidate.scan, data: data, pdf: true, page: candidate.page)
                } else { stage = .pages(data, count: count) }
            } else { await read(data, pdf: true, page: 0) }
        } catch is CancellationError {
            // Dismissing the import must never turn into a late auto-save.
        } catch { stage = .failed(error.localizedDescription) }
    }

    private func read(_ data: Data, pdf: Bool, page: Int) async {
        stage = .reading
        do {
            let scan = pdf ? try await TicketRecognizer.scan(pdf: data, page: page) : try await TicketRecognizer.scan(imageData: data)
            await accept(scan, data: data, pdf: pdf, page: page)
        } catch is CancellationError {
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func accept(_ scan: TicketScan, data: Data, pdf: Bool, page: Int) async {
        do {
            try Task.checkCancellation()
            let draft = TicketTextParser.parse(lines: scan.lines, barcodes: scan.barcodes, strictValidity: sharedURL != nil)
            var pass = TicketPass(draft: draft, barcode: scan.barcodes.first)
            if let tripId, !pass.category.isPass { pass.tripId = tripId }
            if PassStyle.suggested(forOperator: draft.operatorName) == nil, let color = scan.suggestedColor {
                pass.style = PassStyle(background: color)
            }
            if sharedURL != nil, TicketImportPolicy.canAddAutomatically(draft, barcodes: scan.barcodes) {
                let saved = try await store.add(pass, document: data, kind: pdf ? .pdf : .image, page: page, deduplicate: true)
                stage = .added(saved, duplicate: saved.id != pass.id)
            } else {
                stage = .review(.new(pass, document: data, kind: pdf ? .pdf : .image, page: page,
                                     codes: scan.barcodes, colorFromTicket: scan.suggestedColor))
            }
        } catch is CancellationError {
        } catch { stage = .failed(error.localizedDescription) }
    }

    private func added(_ pass: TicketPass, duplicate: Bool) -> some View {
        VStack(spacing: 20) {
            Image(systemName: duplicate ? "ticket" : "checkmark.circle.fill")
                .font(.system(size: 48)).foregroundStyle(Color.appAccent)
            Text(verbatim: duplicate ? L10n.t("Ticket already saved") : L10n.t("Ticket added"))
                .font(.title2.bold()).accessibilityIdentifier("sharedTicketAdded")
            Text(verbatim: pass.displayTitle).font(.headline)
            Text("Please check the dates and code against the original. Recognition does not verify whether a ticket is valid.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            NavigationLink { PassDetailView(passId: pass.id) } label: {
                Label(L10n.t("Check ticket"), systemImage: "ticket").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("checkSharedTicket")
            Button("Done") { dismiss() }.buttonStyle(.bordered)
        }
        .padding().navigationTitle(L10n.t("Add ticket")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// Multi-page PDFs (e.g. outward and return ticket): choose the page with the ticket.
private struct PagePicker: View {
    let data: Data
    let count: Int
    let choose: (Int) -> Void

    var body: some View {
        ScrollView {
            Text("Which page is the ticket?").font(.headline).padding(.top)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(0..<count, id: \.self) { page in
                    PDFPageChoice(data: data, page: page, choose: choose)
                }
            }
            .padding()
        }
        .navigationTitle(L10n.t("Choose page"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PDFPageChoice: View {
    let data: Data
    let page: Int
    let choose: (Int) -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        Button { choose(page) } label: {
            VStack {
                Group {
                    if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
                    else { ProgressView().frame(height: 180) }
                }
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                Text(verbatim: L10n.f("Page %lld", page + 1)).font(.subheadline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ticketPage-\(page)")
        .task {
            let image = await Task.detached(priority: .userInitiated) {
                TicketRecognizer.renderPage(pdf: data, page: page, maxPixels: 420)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
        .onDisappear { thumbnail = nil }
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
