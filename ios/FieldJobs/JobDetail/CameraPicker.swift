import SwiftUI
import UIKit

/// The camera, or the photo library where there is none, as on the simulator.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.sourceType
        picker.delegate = context.coordinator
        return picker
    }

    static var sourceType: UIImagePickerController.SourceType {
        #if targetEnvironment(simulator)
        // The iOS 27 simulator reports a camera, but its shutter stays disabled without a feed.
        return .photoLibrary
        #else
        return UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        #endif
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
