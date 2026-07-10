import SwiftUI
import VisionKit
import Vision

/// Сканер документов: камера → локальный OCR (Vision) → текст в заметку.
struct DocumentScanView: UIViewControllerRepresentable {
    /// Возвращает распознанный текст всех страниц.
    var onComplete: (String) -> Void
    var onCancel: () -> Void

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: (String) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [CGImage] = []
            for pageIndex in 0..<scan.pageCount {
                if let cgImage = scan.imageOfPage(at: pageIndex).cgImage {
                    images.append(cgImage)
                }
            }
            controller.dismiss(animated: true)

            // OCR в фоне, чтобы не блокировать UI.
            let complete = onComplete
            DispatchQueue.global(qos: .userInitiated).async {
                let text = images
                    .compactMap { Self.recognizeText(in: $0) }
                    .joined(separator: "\n\n")
                DispatchQueue.main.async {
                    complete(text)
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onCancel()
        }

        private static func recognizeText(in image: CGImage) -> String? {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ru-RU", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request])

            let lines = request.results?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
    }
}
