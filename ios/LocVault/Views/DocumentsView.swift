import SwiftUI

struct DocumentsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showUploadFlow = false
    @State private var selectedDocument: DocumentMeta?

    var body: some View {
        NavigationStack {
            Group {
                if appState.documentConsent?.granted == true {
                    documentsList
                } else {
                    consentGate
                }
            }
            .navigationTitle("My documents")
            .task {
                await appState.refreshDocumentConsent()
            }
            .refreshable {
                await appState.refreshDocumentConsent()
            }
            .sheet(isPresented: $showUploadFlow) {
                UploadDocumentSheet()
            }
            .sheet(item: $selectedDocument) { document in
                DocumentDetailView(document: document)
            }
        }
    }

    private var documentsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                checklistCard

                Button {
                    authenticateThenRun(reason: "Verify it's you before adding a document") {
                        showUploadFlow = true
                    }
                } label: {
                    Label("Scan a document", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !appState.documents.isEmpty {
                    Text("All documents")
                        .font(.headline)
                    ForEach(appState.documents) { document in
                        Button {
                            authenticateThenRun(reason: "Verify it's you before viewing this document") {
                                selectedDocument = document
                            }
                        } label: {
                            documentRow(document)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 8) {
                    Button("Stop storing documents", role: .destructive) {
                        Task { await appState.revokeDocumentConsent() }
                    }
                    .frame(maxWidth: .infinity)

                    Text("This does not delete documents already stored — delete those individually. It only stops you from uploading new ones until you opt back in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    /// At-a-glance checklist: which of the core document types are on file.
    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your documents")
                .font(.headline)

            ForEach(DocumentType.coreChecklist) { type in
                let onFile = appState.documents.contains { $0.type == type }
                HStack(spacing: 10) {
                    Image(systemName: onFile ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(onFile ? .green : .secondary)
                    Text(type.label)
                        .foregroundStyle(onFile ? .primary : .secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func documentRow(_ document: DocumentMeta) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.type.icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.label?.isEmpty == false ? document.label! : document.type.label)
                    .fontWeight(.medium)
                Text("\(document.type.label) · \(formattedSize(document.fileSizeBytes)) · \(formattedDate(document.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.primary)
    }

    private var consentGate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.doc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)

                    Text("Store a document")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Keep an encrypted copy of important documents — like your ID or Social Security card — so you always have access, even if the physical copy is lost. This is separate from location sharing; you can use one without the other.")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let disclosure = appState.documentDisclosure {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disclosure · v\(disclosure.version)")
                            .font(.headline)
                        ScrollView {
                            Text(disclosure.text)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 280)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ProgressView("Loading disclosure…")
                }

                Button {
                    Task { await appState.grantDocumentConsent() }
                } label: {
                    Text("Allow document storage")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoading)
            }
            .padding()
        }
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formattedDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }

    /// Requires a fresh Face ID/passcode check before running `action` — a
    /// step-up on top of the app-level lock, specific to touching documents.
    private func authenticateThenRun(reason: String, action: @escaping () -> Void) {
        Task {
            if await BiometricAuth.authenticate(reason: reason) {
                action()
            } else {
                appState.errorMessage = "Authentication failed."
            }
        }
    }
}

// MARK: - Upload wizard

private enum UploadStep {
    case chooseType
    case scanAndLabel(DocumentType)
    case success(DocumentMeta)
}

struct UploadDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: UploadStep = .chooseType

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseType:
                    ChooseDocumentTypeStep { type in
                        withAnimation { step = .scanAndLabel(type) }
                    }
                case .scanAndLabel(let type):
                    ScanDocumentStep(documentType: type) { meta in
                        withAnimation { step = .success(meta) }
                    }
                case .success(let meta):
                    UploadSuccessStep(document: meta) {
                        withAnimation { step = .chooseType }
                    } onDone: {
                        dismiss()
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if case .success = step {
                        EmptyView()
                    } else {
                        stepDots
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    switch step {
                    case .chooseType:
                        Button("Cancel") { dismiss() }
                    case .scanAndLabel:
                        Button("Back") { withAnimation { step = .chooseType } }
                    case .success:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .chooseType: return "Add a document"
        case .scanAndLabel(let type): return type.label
        case .success: return "Saved"
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Circle().fill(isPastStepOne ? Color.accentColor : Color(.systemGray4))
                .frame(width: 6, height: 6)
        }
    }

    private var isPastStepOne: Bool {
        if case .chooseType = step { return false }
        return true
    }
}

/// Step 1: pick what kind of document this is. Shows a green check and how
/// many are already on file for each type, so the checklist context carries
/// through into the flow itself.
private struct ChooseDocumentTypeStep: View {
    @EnvironmentObject private var appState: AppState
    let onSelect: (DocumentType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What are you adding?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(DocumentType.allCases) { type in
                    Button {
                        onSelect(type)
                    } label: {
                        typeRow(type)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func typeRow(_ type: DocumentType) -> some View {
        let count = appState.documents.filter { $0.type == type }.count
        return HStack(spacing: 14) {
            Image(systemName: type.icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.label).fontWeight(.medium)
                Text(count > 0 ? "\(count) on file" : "Not on file yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if count > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.primary)
    }
}

/// Step 2: label it (optional) and actually scan it.
private struct ScanDocumentStep: View {
    let documentType: DocumentType
    let onUploaded: (DocumentMeta) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var label = ""
    @State private var showScanner = false
    @State private var scanError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: documentType.icon)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text(documentType.label)
                        .fontWeight(.medium)
                }
            }

            Section("Label (optional)") {
                TextField("e.g. \"Current license\"", text: $label)
            }

            if let scanError {
                Section {
                    Text(scanError)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan document", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isUploadingDocument || !DocumentScannerView.isSupported)
            } footer: {
                if !DocumentScannerView.isSupported {
                    Text("Document scanning isn't available on this device/simulator.")
                }
            }

            if appState.isUploadingDocument {
                HStack {
                    ProgressView()
                    Text("Uploading, encrypting…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { result in
                showScanner = false
                handleScanResult(result)
            }
            .ignoresSafeArea()
        }
    }

    private func handleScanResult(_ result: Result<[UIImage], Error>) {
        switch result {
        case .failure(let error):
            scanError = error.localizedDescription
        case .success(let images):
            guard !images.isEmpty else { return }
            Task {
                let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                var lastMeta: DocumentMeta?
                for (index, image) in images.enumerated() {
                    guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
                    var pageLabel: String? = trimmedLabel.isEmpty ? nil : trimmedLabel
                    if images.count > 1 {
                        let suffix = "page \(index + 1)"
                        pageLabel = pageLabel.map { "\($0) (\(suffix))" } ?? suffix.capitalized
                    }
                    guard let meta = await appState.uploadDocument(type: documentType, label: pageLabel, imageData: data) else {
                        scanError = appState.errorMessage
                        return
                    }
                    lastMeta = meta
                }
                if let lastMeta {
                    onUploaded(lastMeta)
                }
            }
        }
    }
}

/// Step 3: confirmation, with the option to add another right away.
private struct UploadSuccessStep: View {
    let document: DocumentMeta
    let onAddAnother: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("\(document.type.label) saved")
                .font(.title3.bold())

            Text("It's encrypted and ready whenever you need it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button("Add another document", action: onAddAnother)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail viewer

struct DocumentDetailView: View {
    let document: DocumentMeta
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else if let loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(loadError)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView("Decrypting…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(document.label?.isEmpty == false ? document.label! : document.type.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .alert("Delete this document?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await appState.deleteDocument(document.id)
                        dismiss()
                    }
                }
            } message: {
                Text("This permanently deletes the stored copy. This cannot be undone.")
            }
            .task {
                await loadDocument()
            }
        }
    }

    private func loadDocument() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchDocument(id: document.id)
            guard let data = Data(base64Encoded: response.fileBase64), let uiImage = UIImage(data: data) else {
                loadError = "Couldn't read this document's contents."
                return
            }
            image = uiImage
        } catch {
            loadError = error.localizedDescription
        }
    }
}
