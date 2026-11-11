// Cut the subject out of a photo using Vision's foreground instance mask.
//
// Usage: cutout <input.jpg> <output.png>
//
// Produces a transparent PNG of the most prominent instance (the motorcycle),
// which the sprite pipeline can then matte-free downscale into pixel art.

import Foundation
import Vision
import CoreImage
import AppKit

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail(2, "usage: cutout <input> <output.png>") }

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let context = CIContext()

guard let source = CIImage(contentsOf: inputURL) else { fail(3, "cannot read \(args[1])") }

let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: source, options: [:])
do {
    try handler.perform([request])
} catch {
    fail(4, "vision failed: \(error)")
}

guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
    fail(5, "no foreground instance found")
}

let buffer: CVPixelBuffer
do {
    buffer = try observation.generateMaskedImage(
        ofInstances: observation.allInstances,
        from: handler,
        croppedToInstancesExtent: false
    )
} catch {
    fail(6, "mask generation failed: \(error)")
}

var masked = CIImage(cvPixelBuffer: buffer)

// The mask is returned cropped to the instance extent; map it back into the
// original image so the cutout keeps the source framing.
if observation.allInstances.count > 0 {
    let extent = masked.extent
    masked = masked.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
}

guard let cgImage = context.createCGImage(masked, from: masked.extent) else {
    fail(7, "cannot render CGImage")
}

let rep = NSBitmapImageRep(cgImage: cgImage)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fail(8, "cannot encode PNG")
}
do {
    try data.write(to: outputURL)
} catch {
    fail(9, "cannot write \(args[2]): \(error)")
}
print("ok \(outputURL.lastPathComponent)")
