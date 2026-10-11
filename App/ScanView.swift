import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage

struct ScanView: View {
    @Environment(\.dismiss) var dismiss
    let scanned: (String) -> Void
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var authorized = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Design.card)
                    if authorized { LiveQRScanner(error: $error, scanned: scanned).clipShape(RoundedRectangle(cornerRadius: 24)) }
                    RoundedRectangle(cornerRadius: 12).stroke(Design.accent, style: StrokeStyle(lineWidth: 3, dash: [35, 120])).frame(width: 230, height: 230).allowsHitTesting(false)
                }.frame(height: 350)
                Text("наведи камеру на qr-код").font(.headline)
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !authorized {
                        Button("открыть настройки") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                }
                PhotosPicker(selection: $photo, matching: .images) { Label("выбрать из фото", systemImage: "photo") }
                    .buttonStyle(.bordered)
                Spacer()
            }.padding(20).pageBackground()
            .navigationTitle("сканировать qr").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("закрыть") { dismiss() } } }
            .task {
                authorized = await AVCaptureDevice.requestAccess(for: .video)
                if !authorized { error = "разреши доступ к камере или выбери изображение" }
            }
            .onChange(of: photo) { _, item in
                Task {
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self), data.count <= 20 * 1024 * 1024,
                              let image = CIImage(data: data),
                              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
                              let code = detector.features(in: image).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first else {
                            error = "на изображении не найден qr-код"; return
                        }
                        scanned(code)
                    } catch { self.error = "не удалось прочитать изображение" }
                }
            }
        }
    }
}

final class CameraPreview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct LiveQRScanner: UIViewRepresentable {
    @Binding var error: String?
    let scanned: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(error: $error, scanned: scanned) }
    func makeUIView(context: Context) -> CameraPreview {
        let view = CameraPreview()
        view.preview.session = context.coordinator.session
        view.preview.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }
    func updateUIView(_ view: CameraPreview, context: Context) {}
    static func dismantleUIView(_ view: CameraPreview, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "baha.camera")
        private let error: Binding<String?>
        private let scanned: (String) -> Void
        private var delivered = false
        init(error: Binding<String?>, scanned: @escaping (String) -> Void) { self.error = error; self.scanned = scanned }
        func start() {
            queue.async {
                do {
                    guard let camera = AVCaptureDevice.default(for: .video) else { throw NSError(domain: "camera", code: 0) }
                    let input = try AVCaptureDeviceInput(device: camera)
                    let output = AVCaptureMetadataOutput()
                    self.session.beginConfiguration()
                    guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                        self.session.commitConfiguration(); throw NSError(domain: "camera", code: 1)
                    }
                    self.session.addInput(input); self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.qr]
                    self.session.commitConfiguration()
                    self.session.startRunning()
                } catch { DispatchQueue.main.async { self.error.wrappedValue = "камера недоступна; выбери qr из фото" } }
            }
        }
        func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered, let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
            delivered = true; scanned(value); stop()
        }
    }
}
