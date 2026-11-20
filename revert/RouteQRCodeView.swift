import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct RouteQRCodeItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

struct RouteQRCodeView: View {
    let item: RouteQRCodeItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityLabel("QR code for \(item.name)")
                } else {
                    ProgressView().controlSize(.large)
                }
                Text(item.name)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(MapUI.ink)
                Text("Scan with a phone camera to open the route in Revert.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .pulseBackground()
            .navigationTitle("Route QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { image = makeQRCode() }
        }
    }

    private func makeQRCode() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(item.url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
