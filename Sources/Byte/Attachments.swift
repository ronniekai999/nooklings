import Foundation
import ImageIO
import CoreGraphics

struct AttachmentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ImageAttachment {
    static let maxFileBytes = 25 * 1024 * 1024
    static let maxDimension = 1568

    static func prepare(url: URL) throws -> Data {
        guard url.isFileURL else { throw AttachmentError(message: "Choose a local image file.") }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maxFileBytes else { throw AttachmentError(message: "Choose an image smaller than 25 MB.") }
        return try prepare(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Called on a worker task. ImageIO downsamples before decoding full pixels.
    static func prepare(data: Data) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= maxFileBytes else { throw AttachmentError(message: "Choose an image smaller than 25 MB.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else {
            throw AttachmentError(message: "This image is unreadable or exceeds 100 megapixels. Choose a smaller image.")
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary), let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw AttachmentError(message: "Couldn't prepare this image. Try PNG, JPEG, HEIC, or TIFF.")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        context.draw(image, in: rect)
        let output = NSMutableData()
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw AttachmentError(message: "Couldn't encode this image.")
        }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 5 * 1024 * 1024 else {
            throw AttachmentError(message: "The prepared image is too large. Choose a smaller image.")
        }
        try Task.checkCancellation()
        return output as Data
    }
}

enum AttachmentStore {
    /// A corrupt/unreadable record makes reachability unknowable, so preserve
    /// every sidecar. Only UUID JPEGs owned by the app are eligible for deletion.
    static func prune(root: URL, liveIDs: Set<String>) throws -> Int {
        let fm = FileManager.default, images = root.appendingPathComponent("images")
        guard fm.fileExists(atPath: images.path) else { return 0 }
        guard try images.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw AttachmentError(message: "Image cleanup skipped a linked image directory.")
        }
        var references = liveIDs
        var records = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent == "history.json" || ($0.lastPathComponent.hasPrefix("history-recovery-") && $0.pathExtension == "json") }
        let archives = root.appendingPathComponent("archives")
        if fm.fileExists(atPath: archives.path) {
            records += try fm.contentsOfDirectory(at: archives, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        }
        for record in records {
            do {
                let list = try JSONDecoder().decode([ByteModel.Turn].self, from: Data(contentsOf: record))
                for id in list.compactMap(\.imageId) {
                    guard UUID(uuidString: id) != nil else { throw AttachmentError(message: "Invalid image reference") }
                    references.insert(id)
                }
            } catch {
                throw AttachmentError(message: "No images removed: \(record.lastPathComponent) needs recovery before cleanup is safe.")
            }
        }
        var count = 0
        for image in try fm.contentsOfDirectory(at: images, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let id = image.deletingPathExtension().lastPathComponent
            guard image.pathExtension == "jpg", UUID(uuidString: id) != nil, !references.contains(id) else { continue }
            let values = try image.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try fm.removeItem(at: image); count += 1
        }
        return count
    }
}
