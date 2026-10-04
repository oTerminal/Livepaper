import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import LivepaperScene

/// The constant rate a sprite sheet is written at: its shortest frame's, 60 at
/// most, on a clock of 6000 ticks a second, which holds every common frame time
/// (1/10, 1/24, 1/25, 1/30, 0.07 s…) exactly.
public func spriteSheetRate(_ durations: [Double]) -> FrameRate {
    let shortest = durations.filter { $0.isFinite && $0 > 0 }.min() ?? 0.1
    return FrameRate(duration: max(100, Int64((shortest * 6000).rounded())), timescale: 6000)
}

/// Writes a GIF scene's frames as a video file, which the rest
/// of the import then works from as it works from what ffmpeg makes of a GIF:
/// normalised, validated, and made into the optimised copy. So that the one
/// lossy encoding is the optimised copy's own, the frames go in as ProRes.
///
/// Each frame is shown for its own time, on a constant rate: a longer frame is
/// held over the slots it spans (`ConstantRateResampler`, as a transcode does).
/// Frames are laid over the scene's clear colour, since a GIF may be
/// transparent and a wallpaper may not.
@concurrent
func writeSpriteSheetVideo(
    _ sheet: SpriteSheet, over background: [Double], to destination: URL, progress: @escaping @Sendable (Double) -> Void
) async throws {
    guard let first = sheet.frames.first else { throw MediaError.noVideoTrack }
    let canvas = FrameCanvas(size: first.rect.size, background: background)
    let rate = spriteSheetRate(sheet.frames.map(\.duration))
    let total = sheet.frames.reduce(0) { $0 + $1.duration }

    try await onOwnThread { cancellation in
        let job = try SpriteSheetWriter(destination: destination, canvas: canvas, rate: rate, cancellation: cancellation)
        do {
            var resampler = ConstantRateResampler(rate: rate)
            var start = 0.0
            var held: CVPixelBuffer?
            for frame in sheet.frames {
                try cancellation.check()
                let pixels = try canvas.draw(frame, of: sheet, pool: job.pool)
                if let count = resampler.next(pts: start), let held { try job.write(held, times: count) }
                held = pixels
                start += frame.duration
                progress(min(1, start / max(total, 0.001)))
            }
            if let held { try job.write(held, times: resampler.finish(end: start)) }
            try job.finish()
        } catch {
            job.abandon()
            throw error
        }
    }
}

/// The file being written: one ProRes video track, stamped by counting frames.
private final class SpriteSheetWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let destination: URL
    private let rate: FrameRate
    private let cancellation: Cancellation
    private var written: Int64 = 0

    init(destination: URL, canvas: FrameCanvas, rate: FrameRate, cancellation: Cancellation) throws {
        self.destination = destination
        self.rate = rate
        self.cancellation = cancellation
        writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        writer.movieTimeScale = rate.timescale
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422,
            AVVideoWidthKey: canvas.width,
            AVVideoHeightKey: canvas.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.mediaTimeScale = rate.timescale
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: canvas.width,
            kCVPixelBufferHeightKey as String: canvas.height,
        ])
        guard writer.canAdd(input) else { throw MediaError.writeFailed("the writer does not take ProRes") }
        writer.add(input)
        guard writer.startWriting() else { throw MediaError.writeFailed(describe(writer.error)) }
        writer.startSession(atSourceTime: .zero)
    }

    /// Buffers of the video's size, once writing has started.
    var pool: CVPixelBufferPool? { adaptor.pixelBufferPool }

    func write(_ pixels: CVPixelBuffer, times count: Int) throws {
        for _ in 0..<count {
            while !input.isReadyForMoreMediaData {
                try cancellation.check()
                guard writer.status == .writing else { throw MediaError.writeFailed(describe(writer.error)) }
                Thread.sleep(forTimeInterval: 0.002)
            }
            let time = CMTime(value: written * rate.duration, timescale: rate.timescale)
            guard adaptor.append(pixels, withPresentationTime: time) else { throw MediaError.writeFailed(describe(writer.error)) }
            written += 1
        }
    }

    /// Ends the file where its frames end.
    func finish() throws {
        try cancellation.check()
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: written * rate.duration, timescale: rate.timescale))
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else { throw MediaError.writeFailed(describe(writer.error)) }
    }

    /// Leaves no file behind.
    func abandon() {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: destination)
    }
}

/// Where each frame is drawn: the video's size, with even sides as encoders
/// like them, over the scene's clear colour.
private struct FrameCanvas: Sendable {
    let width: Int
    let height: Int
    let background: [Double]

    init(size: CGSize, background: [Double]) {
        func even(_ side: CGFloat) -> Int {
            let pixels = max(2, Int(side.rounded(.up)))
            return pixels + pixels % 2
        }
        width = even(size.width)
        height = even(size.height)
        self.background = background.count == 3 ? background : [0, 0, 0]
    }

    func draw(_ frame: SpriteSheet.Frame, of sheet: SpriteSheet, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) }
        if made == nil { CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made) }
        guard let pixels = made, let image = sheet.image(of: frame) else { throw MediaError.writeFailed("a frame could not be drawn") }

        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { throw MediaError.writeFailed("a frame could not be drawn") }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(red: background[0], green: background[1], blue: background[2], alpha: 1)
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        return pixels
    }
}
