import XCTest
import ImageIO
import AppKit
@testable import Byte

final class AttachmentTests: XCTestCase {
    func testCleanupPreservesLiveArchiveAndRecoveryReferencesAndUnknownFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("images"), archives = root.appendingPathComponent("archives")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        let ids = (0..<5).map { _ in UUID().uuidString }
        for id in ids { try Data("sidecar".utf8).write(to: images.appendingPathComponent(id + ".jpg")) }
        try Data("user file".utf8).write(to: images.appendingPathComponent("keep.jpg"))
        for (id, path) in zip(ids.prefix(3), ["history.json", "archives/chat-old.json", "history-recovery-copy.json"]) {
            let turn = ByteModel.Turn(role: .user, text: "Saved image", imageId: id)
            try JSONEncoder().encode([turn]).write(to: root.appendingPathComponent(path))
        }
        XCTAssertEqual(try AttachmentStore.prune(root: root, liveIDs: [ids[3]]), 1)
        for id in ids.prefix(4) { XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent(id + ".jpg").path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent("keep.jpg").path))
    }

    func testUnusableRecoveryRecordMakesCleanupPreserveEveryImage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let image = images.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data("potentially needed".utf8).write(to: image)
        try Data("[{\"wrong\":\"schema\"}]".utf8).write(to: root.appendingPathComponent("history-recovery-broken.json"))
        XCTAssertThrowsError(try AttachmentStore.prune(root: root, liveIDs: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    }

    func testLargeImageDownsamplesBeforeStorageAndInvalidFilesReportErrors() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let source = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let jpeg = try ImageAttachment.prepare(data: source)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1568)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 784)
        XCTAssertLessThan(jpeg.count, 5 * 1024 * 1024)
        XCTAssertThrowsError(try ImageAttachment.prepare(data: Data("not an image".utf8)))
        XCTAssertThrowsError(try ImageAttachment.prepare(data: Data(count: ImageAttachment.maxFileBytes + 1)))
    }
}
