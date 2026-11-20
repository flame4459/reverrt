import SwiftUI
import Combine
import ReplayKit

@MainActor
final class ReplayExporter: ObservableObject {
    @Published var error: String?
    @Published var preview: ReplayPreviewItem?
    @Published var isRecording = false

    func start() async -> Bool {
        guard RPScreenRecorder.shared().isAvailable else {
            error = "Screen recording is not available on this device."
            return false
        }
        guard !isRecording else { return true }
        RPScreenRecorder.shared().isMicrophoneEnabled = false
        isRecording = true
        let started = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            RPScreenRecorder.shared().startRecording { [weak self] error in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }
                    if let error {
                        self.error = error.localizedDescription
                        self.isRecording = false
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(returning: true)
                    }
                }
            }
        }
        return started
    }

    func stop() async {
        guard isRecording else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            RPScreenRecorder.shared().stopRecording { [weak self] preview, error in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.isRecording = false
                    if let preview {
                        self.preview = ReplayPreviewItem(controller: preview)
                    } else if let error {
                        self.error = error.localizedDescription
                    }
                    continuation.resume()
                }
            }
        }
    }
}

struct ReplayPreviewItem: Identifiable {
    let id = UUID()
    let controller: RPPreviewViewController
}

struct ReplayPreviewSheet: UIViewControllerRepresentable {
    let controller: RPPreviewViewController

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        controller.previewControllerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
        func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
            previewController.dismiss(animated: true)
        }
    }
}
