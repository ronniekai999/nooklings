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
        .accessibilityHidden(true)
    }
}

enum CompanionArtwork {
    // Fixed assets, loaded at first access. Never decode PNGs on every animation tick.
    private static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Byte_Byte.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }

    private static let frames: [Companion: [CGImage]] = {
        var result: [Companion: [CGImage]] = [:]
        for companion in Companion.allCases {
            guard let url = resourceBundle.url(forResource: companion.rawValue,
                                              withExtension: "png", subdirectory: "Companions"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let w = atlas.width / 3, h = atlas.height / 2
            result[companion] = ByteSprite.Mood.allCases.compactMap { mood in
                // Discard the empty top/bottom gutter, keeping all poses on the same canvas.
                let rect = CGRect(x: (mood.rawValue % 3) * w,
                                  y: (mood.rawValue / 3) * h + 40,
                                  width: w, height: h - 70)
                return atlas.cropping(to: rect)
            }
        }
        return result
    }()

    static func frame(_ companion: Companion, mood: ByteSprite.Mood) -> CGImage? {
        guard let images = frames[companion], images.count == ByteSprite.Mood.allCases.count else { return nil }
        return images[mood.rawValue]
    }
}
