import SwiftUI
import AppKit
import ImageIO

/// Six photographic expressions, cached once per companion. Existing movement
/// animations still operate on this view; care adds eating, drinking and sleep.
struct ByteSprite: View {
    enum Mood: Int, CaseIterable {
        case neutral, happy, thinking, eating, drinking, sleeping
    }
    var scale: CGFloat = 0.82
    var mood: Mood = .neutral
    var companion: Companion = .trex

    var body: some View {
        Group {
            if let image = CompanionArtwork.frame(companion, mood: mood) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 160 * scale, height: 116 * scale)
    }
}

enum CompanionArtwork {
    // Fixed assets, loaded at first access. Never decode PNGs on every animation tick.
    private static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Nooklings_Byte.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }

    /// Decodes each atlas once and caches isolated expressions on a shared baseline.
    private static let frames: [Companion: [CGImage]] = {
        var result: [Companion: [CGImage]] = [:]
        for companion in Companion.allCases {
            guard let url = resourceBundle.url(forResource: companion.rawValue,
                                              withExtension: "png", subdirectory: "Companions"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let w = atlas.width / 3, h = atlas.height / 2
            result[companion] = ByteSprite.Mood.allCases.compactMap { mood in
                // The baby atlases use full cells so ears, paws, fins, and tails
                // stay intact. Crop before shifting to avoid sampling a neighbor.
                let row = mood.rawValue / 3
                guard let cell = atlas.cropping(to: CGRect(x: (mood.rawValue % 3) * w,
                                                          y: row * h, width: w, height: h)) else { return nil }
                guard row == 1 else { return cell }
                // Match the lower poses to the standing baseline in each bundled atlas.
                // Each shift stays inside the isolated cell's transparent bottom margin.
                let lowerRowShift: CGFloat
                switch companion {
                case .trex: lowerRowShift = 77
                case .dolphin: lowerRowShift = 45
                case .dog: lowerRowShift = 65
                case .cat: lowerRowShift = 66
                case .panda: lowerRowShift = 70
                case .duck: lowerRowShift = 44
                }
                guard let canvas = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                             bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                canvas.draw(cell, in: CGRect(x: 0, y: -lowerRowShift, width: w, height: h))
                return canvas.makeImage()
            }
        }
        return result
    }()

    /// Returns a cached expression, or nil if the companion's full atlas could not load.
    static func frame(_ companion: Companion, mood: ByteSprite.Mood) -> CGImage? {
        guard let images = frames[companion], images.count == ByteSprite.Mood.allCases.count else { return nil }
        return images[mood.rawValue]
    }
}
