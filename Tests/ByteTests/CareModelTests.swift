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
    func testShortcutOpensAndRefocusesWithoutTogglingOrReadingContext() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        var opens = 0, focuses = 0
        model.onChatOpenChanged = { if $0 { opens += 1 } }
        model.onFocusChat = { focuses += 1 }
        model.draft = "Keep my draft"
        model.openAndFocusChat()
        let first = model.focusRequest
        model.openAndFocusChat()
        XCTAssertTrue(model.chatOpen)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(focuses, 2)
        XCTAssertNotEqual(first, model.focusRequest)
        XCTAssertEqual(model.draft, "Keep my draft")
        XCTAssertTrue(model.turns.isEmpty)
        XCTAssertNil(model.pendingImage)
        model.toggleChat()
        XCTAssertEqual(model.draft, "Keep my draft")
    }

    @MainActor
    func testShortcutPreferencePersistsAndRejectsUnmodifiedKeys() throws {
        let f = try CareFixture(); defer { f.clean() }
        let shortcut = GlobalShortcut(defaults: f.defaults)
        XCTAssertFalse(shortcut.set(ShortcutSpec(keyCode: 0, modifiers: 0, keyLabel: "A")))
        XCTAssertNotNil(shortcut.error)
        XCTAssertTrue(shortcut.set(.standard))
        XCTAssertEqual(GlobalShortcut(defaults: f.defaults).configuration, .standard)
        XCTAssertTrue(shortcut.set(nil))
        XCTAssertNil(GlobalShortcut(defaults: f.defaults).configuration)
    }

    @MainActor
    func testCareDashboardRendersForEveryCompanion() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        var rendered = Set<Data>()
        for companion in Companion.allCases {
            XCTAssertTrue(model.selectCompanion(companion))
            if let directory = ProcessInfo.processInfo.environment["NOOKLINGS_SNAPSHOT_DIRECTORY"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let portrait = try XCTUnwrap(CompanionArtwork.frame(companion, mood: .happy))
                let bitmap = NSBitmapImageRep(cgImage: portrait)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: url.appendingPathComponent("portrait-\(companion.rawValue).png"))
            }
            let rgb = companion.tint
            for scheme in [ColorScheme.light, .dark] {
                let dashboard = CareView(model: model, accent: Color(red: rgb.0, green: rgb.1, blue: rgb.2),
                                         mood: .happy, phase: 0, isBusy: false, onCare: { _ in })
                let view = dashboard.dashboardContent
                    .frame(width: 370)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage, "Couldn't render \(companion.name)")
                XCTAssertEqual(image.width, 740)
                XCTAssertGreaterThan(image.height, 1400, "All care cards should be in the full-content preview")
                let bitmap = NSBitmapImageRep(cgImage: image)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertTrue(rendered.insert(data).inserted, "Different companions must not produce the same blank preview")
                if let directory = ProcessInfo.processInfo.environment["NOOKLINGS_SNAPSHOT_DIRECTORY"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    let file = url.appendingPathComponent("\(companion.rawValue)-\(scheme == .dark ? "dark" : "light").png")
                    try data.write(to: file)
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
    func testStartingCareDoesNotLaunchACompetingCheckIn() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        model.pet.hunger = 10
        model.pet.lastCheckIn = .distantPast
        var greeted = false
        model.onCheckIn = { _ in greeted = true }
        XCTAssertNotNil(model.beginCare(.meal))
        XCTAssertFalse(greeted)
        XCTAssertEqual(model.activeCare, .meal)
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

    @MainActor
    func testCorruptCurrentSaveAllowsHealthyCompanionAndFuturePersistence() throws {
        let f = try CareFixture(); defer { f.clean() }
        let bad = Data("keep this damaged save".utf8)
        let file = f.root.appendingPathComponent("pet.json")
        try bad.write(to: file)
        let model = f.model()
        XCTAssertNil(model.beginCare(.meal), "Don't pretend to save care on a protected file")
        XCTAssertTrue(model.selectCompanion(.cat))
        model.pet.hunger = 20
        model.completeCare(try XCTUnwrap(model.beginCare(.meal)))
        model.prepareForTermination()
        XCTAssertEqual(try Data(contentsOf: file), bad)
        let reloaded = f.model()
        XCTAssertEqual(reloaded.companion, .cat)
        XCTAssertEqual(reloaded.pet.hunger, model.pet.hunger)
        XCTAssertEqual(reloaded.pet.careCount, 1)
        XCTAssertFalse(reloaded.selectCompanion(.trex))
        XCTAssertEqual(reloaded.companion, .cat)
    }
}
