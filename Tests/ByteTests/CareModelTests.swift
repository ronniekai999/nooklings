import XCTest
import SwiftUI
import AppKit
@testable import Byte

private final class CareTestKeys: APIKeyStoring {
    func read() throws -> String? { nil }
    func save(_ key: String) throws {}
    func remove() throws {}
}

@MainActor
private struct CareFixture {
    let root: URL
    let defaults: UserDefaults
    let suite: String
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "CareTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    func model() -> ByteModel {
        ByteModel(configDirectory: root, defaults: defaults, keyStore: CareTestKeys(), chatGPTStore: CareTestKeys(),
                  chatGPTCredentialLock: ChatGPTCredentialLock(url: root.appendingPathComponent("lock")),
                  environment: [:], now: { start })
    }
    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

final class CareModelTests: XCTestCase {
    @MainActor
    func testCareDashboardRendersForEveryCompanion() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        for companion in Companion.allCases {
            XCTAssertTrue(model.selectCompanion(companion))
            let rgb = companion.tint
            for scheme in [ColorScheme.light, .dark] {
                let view = CareView(model: model, accent: Color(red: rgb.0, green: rgb.1, blue: rgb.2),
                                    mood: .happy, phase: 0, isBusy: false, onCare: { _ in })
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage, "Couldn't render \(companion.name)")
                XCTAssertEqual(image.width, 740)
                XCTAssertEqual(image.height, 1240)
                if let directory = ProcessInfo.processInfo.environment["BYTE_SNAPSHOT_DIRECTORY"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    let file = url.appendingPathComponent("\(companion.rawValue)-\(scheme == .dark ? "dark" : "light").png")
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
                }
            }
        }
    }

    @MainActor
    func testSwitchingPreservesIndependentNeedsAndRestoresSelection() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        model.pet.hunger = 31
        XCTAssertTrue(model.selectCompanion(.cat))
        XCTAssertEqual(model.pet.hunger, 80)
        model.pet.hunger = 57
        XCTAssertTrue(model.selectCompanion(.trex))
        XCTAssertEqual(model.pet.hunger, 31)
        XCTAssertTrue(model.selectCompanion(.cat))
        XCTAssertEqual(model.pet.hunger, 57)
        model.prepareForTermination()
        let loaded = f.model()
        XCTAssertEqual(loaded.companion, .cat)
        XCTAssertEqual(loaded.pet.hunger, 57)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("pet.json").path))
    }

    @MainActor
    func testCareReservationBlocksOverlapAndSwitchAndCompletesOnce() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        model.pet.hunger = 20
        let token = try XCTUnwrap(model.beginCare(.meal))
        XCTAssertNil(model.beginCare(.meal))
        XCTAssertFalse(model.selectCompanion(.panda))
        XCTAssertEqual(model.pet.hunger, 20)
        model.completeCare(token)
        model.completeCare(token)
        XCTAssertEqual(model.pet.hunger, 58)
        XCTAssertEqual(model.pet.careCount, 1)
        XCTAssertNil(model.activeCare)
    }

    @MainActor
    func testCancelledAnimationDoesNotAwardCareOrAcceptStaleCompletion() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        model.pet.hunger = 20
        let cancelled = try XCTUnwrap(model.beginCare(.meal))
        model.cancelCare(cancelled)
        let current = try XCTUnwrap(model.beginCare(.snack))
        model.completeCare(cancelled)
        XCTAssertEqual(model.pet.hunger, 20)
        XCTAssertEqual(model.activeCare, .snack)
        model.completeCare(current)
        XCTAssertEqual(model.pet.hunger, 36)
        XCTAssertEqual(model.pet.careCount, 1)
    }

    @MainActor
    func testUnreadableTargetDoesNotReplaceCurrentCompanion() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        let bad = Data("broken save".utf8)
        try bad.write(to: f.root.appendingPathComponent("pet-panda.json"))
        XCTAssertFalse(model.selectCompanion(.panda))
        XCTAssertEqual(model.companion, .trex)
        XCTAssertNotNil(model.storageError)
        XCTAssertEqual(try Data(contentsOf: f.root.appendingPathComponent("pet-panda.json")), bad)
    }

    @MainActor
    func testCorruptLegacySaveIsNeverOverwrittenOnLaunchOrTermination() throws {
        let f = try CareFixture(); defer { f.clean() }
        let bad = Data("preserve this".utf8)
        let file = f.root.appendingPathComponent("pet.json")
        try bad.write(to: file)
        let model = f.model()
        model.tickPet()
        model.prepareForTermination()
        XCTAssertEqual(try Data(contentsOf: file), bad)
        XCTAssertNotNil(model.storageError)
    }
}
