import Foundation
import ImageIO

// Exercise Bundle's real resource lookup from a relocated app. SwiftPM's native
// and universal builders use different internal resource-bundle layouts.
let source = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Nooklings.app")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("nooklings-verify-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let relocated = temporary.appendingPathComponent("Nooklings.app")
try FileManager.default.copyItem(at: source, to: relocated)
guard let app = Bundle(url: relocated), app.bundleIdentifier == "com.ronnie.byte",
      let resourceURL = app.resourceURL?.appendingPathComponent("Nooklings_Byte.bundle"),
      let resources = Bundle(url: resourceURL) else { fatalError("Invalid app identity or resource bundle") }
for animal in ["trex", "dolphin", "dog", "cat", "panda", "duck"] {
    guard let url = resources.url(forResource: animal, withExtension: "png", subdirectory: "Companions"),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == 1536, image.height == 1024 else {
        fatalError("Relocated app cannot load the \(animal) expression atlas")
    }
}
print("Relocated app identity and all six expression atlases verified.")
