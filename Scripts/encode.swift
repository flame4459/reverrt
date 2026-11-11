// Encode a directory of PNG frames into an H.264 MP4.
//
// Usage: encode <frames-dir> <output.mp4> <fps>

import Foundation
import AVFoundation
import CoreImage
import AppKit

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 4 else { fail(2, "usage: encode <frames-dir> <out.mp4> <fps>") }
let folder = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let fps = Int32(args[3]) ?? 24

let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
guard !files.isEmpty else { fail(3, "no PNG frames in \(args[1])") }
guard let first = NSImage(contentsOf: files[0]) else { fail(4, "cannot read first frame") }

let width = Int(first.size.width)
let height = Int(first.size.height)
try? FileManager.default.removeItem(at: output)

guard let writer = try? AVAssetWriter(outputURL: output, fileType: .mp4) else {
    fail(5, "cannot create writer")
}
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ]
)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

var frame: Int64 = 0
for file in files {
    guard let image = NSImage(contentsOf: file) else { continue }
    var rect = CGRect(x: 0, y: 0, width: width, height: height)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { continue }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let pixelBuffer = buffer else { continue }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )
    context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    while !input.isReadyForMoreMediaData { usleep(2000) }
    adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: frame, timescale: fps))
    frame += 1
}

input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()

if writer.status == .completed {
    let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
    print("ok \(output.lastPathComponent) \((size ?? 0) / 1024) KB \(frame) frames")
} else {
    fail(6, "encode failed: \(writer.error?.localizedDescription ?? "unknown")")
}
