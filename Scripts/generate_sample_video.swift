import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo

let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sample Wallpapers")
    .appendingPathComponent("Aurora_Loop.mp4")

try? FileManager.default.removeItem(at: outputURL)

let width = 1920
let height = 1080
let fps: Int32 = 30
let totalSeconds = 6
let totalFrames = totalSeconds * Int(fps)

let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
]

let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
)

writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

var pixelBufferPool = adaptor.pixelBufferPool

for frameIndex in 0..<totalFrames {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
    }

    var pixelBuffer: CVPixelBuffer?
    if let pool = adaptor.pixelBufferPool {
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
    } else {
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
    }

    guard let pb = pixelBuffer else { continue }
    CVPixelBufferLockBaseAddress(pb, [])

    let data = CVPixelBufferGetBaseAddress(pb)!
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    )!

    let t = Double(frameIndex) / Double(totalFrames) * 2.0 * .pi
    let r1 = CGFloat(0.1 + 0.15 * sin(t))
    let g1 = CGFloat(0.2 + 0.2 * cos(t))
    let b1 = CGFloat(0.45 + 0.3 * sin(t + 1.0))

    let r2 = CGFloat(0.4 + 0.3 * cos(t + 2.0))
    let g2 = CGFloat(0.1 + 0.1 * sin(t + 0.5))
    let b2 = CGFloat(0.6 + 0.25 * cos(t))

    let colors = [
        CGColor(red: r1, green: g1, blue: b1, alpha: 1.0),
        CGColor(red: r2, green: g2, blue: b2, alpha: 1.0),
        CGColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1.0)
    ] as CFArray

    let locations: [CGFloat] = [0.0, 0.6, 1.0]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!

    let startX = CGFloat(width) * CGFloat(0.5 + 0.3 * cos(t))
    let startY = CGFloat(height) * CGFloat(0.5 + 0.3 * sin(t))
    let endX = CGFloat(width) * CGFloat(0.5 - 0.3 * cos(t))
    let endY = CGFloat(height) * CGFloat(0.5 - 0.3 * sin(t))

    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: startX, y: startY),
        end: CGPoint(x: endX, y: endY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    CVPixelBufferUnlockBaseAddress(pb, [])

    let presentTime = CMTime(value: Int64(frameIndex), timescale: fps)
    adaptor.append(pb, withPresentationTime: presentTime)
}

input.markAsFinished()
let group = DispatchGroup()
group.enter()
writer.finishWriting {
    group.leave()
}
group.wait()

print("Successfully generated sample video at: \(outputURL.path)")
