import SwiftUI
import PhotosUI

// MARK: - Photo Picker (iOS 16+ PhotosUI)

struct ImagePickerButton: View {
    @Binding var imageData: Data?
    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false

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
                showCamera = true
            } label: {
                Label("Prendre une photo", systemImage: "camera")
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
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    // Resize to max 1200px wide to save storage
                    imageData = resized(data: data, maxWidth: 1200)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(imageData: $imageData)
        }
    }

    private func resized(data: Data, maxWidth: CGFloat) -> Data? {
        guard let ui = UIImage(data: data) else { return data }
        if ui.size.width <= maxWidth { return data }
        let scale = maxWidth / ui.size.width
        let newSize = CGSize(width: maxWidth, height: ui.size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).jpegData(withCompressionQuality: 0.82) { _ in
            ui.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
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
