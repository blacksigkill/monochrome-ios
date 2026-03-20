import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct CompatPhotoPicker<Label: View>: View {
    let label: () -> Label
    let onImagePicked: (UIImage) -> Void

    init(@ViewBuilder label: @escaping () -> Label,
         onImagePicked: @escaping (UIImage) -> Void) {
        self.label = label
        self.onImagePicked = onImagePicked
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ModernPhotoPicker(label: label, onImagePicked: onImagePicked)
        } else {
            LegacyPhotoPicker(label: label, onImagePicked: onImagePicked)
        }
    }
}

@available(iOS 16.0, *)
private struct ModernPhotoPicker<Label: View>: View {
    let label: () -> Label
    let onImagePicked: (UIImage) -> Void
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            label()
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        onImagePicked(image)
                    }
                }
                await MainActor.run {
                    pickerItem = nil
                }
            }
        }
    }
}

private struct LegacyPhotoPicker<Label: View>: View {
    let label: () -> Label
    let onImagePicked: (UIImage) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .sheet(isPresented: $isPresented) {
            LegacyPhotoPickerController(onImagePicked: onImagePicked)
        }
    }
}

private struct LegacyPhotoPickerController: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            self.onImagePicked(image)
                        }
                    }
                }
            }
        }
    }
}
