import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum RecipePhotoImport {
    static let cropAspectRatio: CGFloat = 16 / 9
    static let cropOutputSize = CGSize(width: 1600, height: 900)
    static let maxZoomScale: CGFloat = 4

    static func normalizedRemoteURL(from rawValue: String) -> URL? {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>"))
        guard !candidate.isEmpty else { return nil }

        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }

        guard var components = URLComponents(string: candidate) else { return nil }
        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        guard let host = components.host, !host.isEmpty else { return nil }

        let path = components.path
        if !path.isEmpty {
            components.percentEncodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        }

        if let fragment = components.fragment, !fragment.isEmpty {
            components.percentEncodedFragment = fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment
        }

        if let query = components.query, !query.isEmpty {
            components.percentEncodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        }

        return components.url
    }

    static func preparedImageData(from data: Data, maxWidth: CGFloat = 1200) -> Data? {
    guard let ui = UIImage(data: data) else { return nil }
    guard ui.size.width > maxWidth else { return data }
    
    let scale = maxWidth / ui.size.width
    let newSize = CGSize(width: maxWidth, height: ui.size.height * scale)
    return UIGraphicsImageRenderer(size: newSize).jpegData(withCompressionQuality: 0.82) { _ in
        ui.draw(in: CGRect(origin: .zero, size: newSize))
    }
    }

    static func preparedJPEGData(
    from data: Data,
    maxWidth: CGFloat = cropOutputSize.width,
    compressionQuality: CGFloat = 0.82
) -> Data? {
    guard let ui = UIImage(data: data) else { return nil }

    let outputSize: CGSize
    if ui.size.width > maxWidth {
        let scale = maxWidth / ui.size.width
        outputSize = CGSize(width: maxWidth, height: ui.size.height * scale)
    } else {
        outputSize = ui.size
    }

    return UIGraphicsImageRenderer(size: outputSize).jpegData(withCompressionQuality: compressionQuality) { _ in
        ui.draw(in: CGRect(origin: .zero, size: outputSize))
    }
}

    static func clampedZoomScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), maxZoomScale)
    }

    static func baseFillScale(for imageSize: CGSize, cropSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, cropSize.width > 0, cropSize.height > 0 else { return 1 }
        return max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
    }

    static func clampedOffset(imageSize: CGSize, cropSize: CGSize, zoomScale: CGFloat, offset: CGSize) -> CGSize {
        let clampedZoom = clampedZoomScale(zoomScale)
        let baseScale = baseFillScale(for: imageSize, cropSize: cropSize)
        let displayedSize = CGSize(
            width: imageSize.width * baseScale * clampedZoom,
            height: imageSize.height * baseScale * clampedZoom
        )

        let maxX = max(0, (displayedSize.width - cropSize.width) / 2)
        let maxY = max(0, (displayedSize.height - cropSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    static func renderedImageData(
        from image: UIImage,
        cropSize: CGSize,
        zoomScale: CGFloat,
        offset: CGSize,
        outputSize: CGSize = cropOutputSize
    ) -> Data? {
        guard cropSize.width > 0, cropSize.height > 0, outputSize.width > 0, outputSize.height > 0 else { return nil }

        let clampedZoom = clampedZoomScale(zoomScale)
        let clamped = clampedOffset(imageSize: image.size, cropSize: cropSize, zoomScale: clampedZoom, offset: offset)
        let baseScale = baseFillScale(for: image.size, cropSize: cropSize)
        let displayedSize = CGSize(
            width: image.size.width * baseScale * clampedZoom,
            height: image.size.height * baseScale * clampedZoom
        )
        let imageOrigin = CGPoint(
            x: ((cropSize.width - displayedSize.width) / 2) + clamped.width,
            y: ((cropSize.height - displayedSize.height) / 2) + clamped.height
        )

        let xScale = outputSize.width / cropSize.width
        let yScale = outputSize.height / cropSize.height
        let drawRect = CGRect(
            x: imageOrigin.x * xScale,
            y: imageOrigin.y * yScale,
            width: displayedSize.width * xScale,
            height: displayedSize.height * yScale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: outputSize, format: format).jpegData(withCompressionQuality: 0.86) { _ in
            image.draw(in: drawRect)
        }
    }
}

// MARK: - Photo Picker (iOS 16+ PhotosUI)

struct ImagePickerButton: View {
    @Binding var imageData: Data?
    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showURLImporter = false
    @State private var showPhotoEditor = false
    @State private var remotePhotoURL = ""
    @State private var cameraImageData: Data?
    @State private var imageBeingEdited: UIImage?
    @State private var isImportingRemotePhoto = false
    @State private var importErrorMessage: String?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Current image or placeholder
            ZStack {
                if let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(UIColor.secondarySystemBackground))
                        .frame(height: 220)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("Photo du plat")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .cornerRadius(14)
            .overlay(alignment: .bottomTrailing) {
                photoMenuButton
                    .padding(10)
            }
        }
    }

    private var photoMenuButton: some View {
        Menu {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Choisir une photo", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Importer un fichier", systemImage: "doc.badge.plus")
            }
            Button {
                showURLImporter = true
            } label: {
                Label("Coller une URL", systemImage: "link")
            }
            if imageData != nil {
                Button {
                    beginPhotoEditing(from: imageData, deferPresentation: false)
                } label: {
                    Label("Ajuster le cadrage", systemImage: "viewfinder")
                }
            }
            if cameraAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Prendre une photo", systemImage: "camera")
                }
            }
            if imageData != nil {
                Button(role: .destructive) {
                    imageData = nil
                } label: {
                    Label("Supprimer la photo", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                do {
                    guard let data = try await newItem?.loadTransferable(type: Data.self) else { return }
                    beginPhotoEditing(from: data, deferPresentation: false)
                } catch {
                    importErrorMessage = "Impossible de charger cette photo."
                }
            }
        }
        .onChange(of: cameraImageData) { newData in
            guard let newData else { return }
            beginPhotoEditing(from: newData, deferPresentation: true)
            cameraImageData = nil
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(imageData: $cameraImageData)
        }
        .sheet(isPresented: $showURLImporter) {
            NavigationStack {
                Form {
                    Section("URL de l'image") {
                        TextField("https://example.com/photo.jpg", text: $remotePhotoURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                    }

                    if isImportingRemotePhoto {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Téléchargement en cours…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Importer une image")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            if !isImportingRemotePhoto {
                                remotePhotoURL = ""
                                showURLImporter = false
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importer") {
                            Task {
                                await importRemotePhoto()
                            }
                        }
                        .disabled(isImportingRemotePhoto || remotePhotoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotoEditor, onDismiss: {
            imageBeingEdited = nil
        }) {
            if let imageBeingEdited {
                RecipePhotoEditorView(image: imageBeingEdited) { croppedData in
                    imageData = croppedData
                    self.imageBeingEdited = nil
                    showPhotoEditor = false
                }
            }
        }
        .alert("Impossible d'importer l'image", isPresented: importErrorIsPresented) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var importErrorIsPresented: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    importErrorMessage = nil
                }
            }
        )
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                beginPhotoEditing(from: data, deferPresentation: false)
            } catch {
                importErrorMessage = "Impossible de lire ce fichier."
            }
        }
    }

    @MainActor
    private func importRemotePhoto() async {
        guard let url = RecipePhotoImport.normalizedRemoteURL(from: remotePhotoURL) else {
            importErrorMessage = "Entrez une URL d'image valide."
            return
        }

        isImportingRemotePhoto = true
        defer { isImportingRemotePhoto = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                importErrorMessage = "Le téléchargement a échoué (\(http.statusCode))."
                return
            }

            if let mimeType = response.mimeType, !mimeType.isEmpty, !mimeType.hasPrefix("image/") {
                importErrorMessage = "Cette URL ne retourne pas une image."
                return
            }

            remotePhotoURL = ""
            showURLImporter = false
            beginPhotoEditing(from: data, deferPresentation: true)
        } catch {
            importErrorMessage = "Impossible de télécharger l'image depuis cette URL."
        }
    }

    private func beginPhotoEditing(from data: Data?, deferPresentation: Bool) {
        guard let data, let prepared = RecipePhotoImport.preparedImageData(from: data), let image = UIImage(data: prepared) else {
            importErrorMessage = "Le média choisi n'est pas une image valide."
            return
        }

        let presentEditor = {
            imageBeingEdited = image
            showPhotoEditor = true
        }

        if deferPresentation {
            DispatchQueue.main.async(execute: presentEditor)
        } else {
            presentEditor()
        }
    }
}

struct RecipePhotoEditorView: View {
    let image: UIImage
    let onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let cropWidth = max(geometry.size.width - 32, 1)
                let cropSize = CGSize(width: cropWidth, height: cropWidth / RecipePhotoImport.cropAspectRatio)
                let baseScale = RecipePhotoImport.baseFillScale(for: image.size, cropSize: cropSize)
                let displayedSize = CGSize(
                    width: image.size.width * baseScale * zoomScale,
                    height: image.size.height * baseScale * zoomScale
                )

                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.black)

                        Image(uiImage: image)
                            .resizable()
                            .frame(width: displayedSize.width, height: displayedSize.height)
                            .offset(offset)
                            .gesture(dragGesture(cropSize: cropSize))
                            .simultaneousGesture(magnificationGesture(cropSize: cropSize))
                    }
                    .frame(width: cropSize.width, height: cropSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(16)
                    }

                    VStack(spacing: 8) {
                        Text("Pincez pour zoomer, glissez pour recadrer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Le cadrage sera enregistré avec la photo.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }

                    Button("Réinitialiser") {
                        resetCrop()
                    }
                    .disabled(zoomScale == 1 && offset == .zero)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .background(Color(UIColor.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            saveCroppedImage(cropSize: cropSize)
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Ajuster la photo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func magnificationGesture(cropSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newZoomScale = RecipePhotoImport.clampedZoomScale(committedZoomScale * value)
                zoomScale = newZoomScale
                offset = RecipePhotoImport.clampedOffset(
                    imageSize: image.size,
                    cropSize: cropSize,
                    zoomScale: newZoomScale,
                    offset: committedOffset
                )
            }
            .onEnded { value in
                let finalZoomScale = RecipePhotoImport.clampedZoomScale(committedZoomScale * value)
                zoomScale = finalZoomScale
                committedZoomScale = finalZoomScale
                offset = RecipePhotoImport.clampedOffset(
                    imageSize: image.size,
                    cropSize: cropSize,
                    zoomScale: finalZoomScale,
                    offset: offset
                )
                committedOffset = offset
            }
    }

    private func dragGesture(cropSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposedOffset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = RecipePhotoImport.clampedOffset(
                    imageSize: image.size,
                    cropSize: cropSize,
                    zoomScale: zoomScale,
                    offset: proposedOffset
                )
            }
            .onEnded { value in
                let proposedOffset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = RecipePhotoImport.clampedOffset(
                    imageSize: image.size,
                    cropSize: cropSize,
                    zoomScale: zoomScale,
                    offset: proposedOffset
                )
                committedOffset = offset
            }
    }

    private func resetCrop() {
        zoomScale = 1
        committedZoomScale = 1
        offset = .zero
        committedOffset = .zero
    }

    private func saveCroppedImage(cropSize: CGSize) {
        guard let croppedData = RecipePhotoImport.renderedImageData(
            from: image,
            cropSize: cropSize,
            zoomScale: zoomScale,
            offset: offset
        ) else {
            dismiss()
            return
        }

        onSave(croppedData)
        dismiss()
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return picker
        }
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let ui = info[.originalImage] as? UIImage {
                parent.imageData = ui.jpegData(compressionQuality: 0.85)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
