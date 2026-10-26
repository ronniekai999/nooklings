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

@MainActor
private struct ChatPreview: View {
    @ObservedObject var model: ByteModel
    @FocusState private var focused: Bool
    var body: some View { ChatPanel(model: model, focused: $focused, accent: .green).padding(16) }
}

final class CareModelTests: XCTestCase {
    @MainActor
    func testGlobalShortcutRegistrationConflictIsReportedAndCanBeDisabled() throws {
        _ = NSApplication.shared
        let f = try CareFixture(); defer { f.clean() }
        let first = GlobalShortcut(defaults: f.defaults), second = GlobalShortcut(defaults: f.defaults)
        defer { first.stop(); second.stop() }
        // Control + Option + Command + N, chosen to avoid common system shortcuts.
        let spec = ShortcutSpec(keyCode: 45, modifiers: 256 | 2048 | 4096, keyLabel: "N")
        XCTAssertTrue(first.set(spec)); first.start {}
        if let error = first.error { throw XCTSkip("Native hot-key registration unavailable: \(error)") }
        XCTAssertTrue(second.set(spec)); second.start {}
        XCTAssertNotNil(second.error, "A conflicting registration must be visible")
        XCTAssertTrue(first.set(nil))
        XCTAssertTrue(second.set(spec), "Releasing the first registration should make the shortcut available")
        XCTAssertNil(second.error)
    }

    @MainActor
    func testChatControlsRenderAtCompactAndExpandedSizes() throws {
        _ = NSApplication.shared
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        model.hasKey = true
        model.turns = [.init(role: .user, text: "Help me plan a calm afternoon."),
                       .init(role: .byte, text: "Start with one small task, take a walk, then leave a little room for yourself. I’ll keep you company. 🦖")]
        for wide in [false, true] {
            let size = NSSize(width: wide ? 640 : 360, height: wide ? 620 : 440)
            let view = ChatPreview(model: model).environment(\.colorScheme, wide ? .light : .dark)
                .background(wide ? Color(white: 0.95) : Color(white: 0.12))
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(data.count, 1000)
            if let directory = ProcessInfo.processInfo.environment["NOOKLINGS_SNAPSHOT_DIRECTORY"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try data.write(to: url.appendingPathComponent(wide ? "chat-expanded-light.png" : "chat-compact-dark.png"))
            }
            window.orderOut(nil)
        }
    }

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

    /// Confirms duck care is awarded once, survives relaunch, and preserves every older pet.
    @MainActor
    func testPuddleKeepsIndependentCareAndRestWithoutResettingExistingFriends() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        let existing = Companion.allCases.filter { $0 != .duck }
        for (index, companion) in existing.enumerated() {
            XCTAssertTrue(model.selectCompanion(companion))
            model.pet.hunger = Double(30 + index)
        }
        XCTAssertTrue(model.selectCompanion(.duck))
        model.pet.hunger = 40
        let cancelled = try XCTUnwrap(model.beginCare(.explore))
        XCTAssertFalse(model.selectCompanion(.trex), "Keep care attached to the duck until it settles")
        model.cancelCare(cancelled)
        model.completeCare(cancelled)
        XCTAssertEqual(model.pet.hunger, 40)
        let completed = try XCTUnwrap(model.beginCare(.explore))
        model.completeCare(completed)
        model.completeCare(completed)
        XCTAssertEqual(model.pet.hunger, 46)
        XCTAssertEqual(model.pet.careCount, 1)
        model.completeCare(try XCTUnwrap(model.beginCare(.rest)))
        model.prepareForTermination()
        let loaded = f.model()
        XCTAssertEqual(loaded.companion, .duck)
        XCTAssertEqual(loaded.pet.hunger, 46)
        XCTAssertEqual(loaded.pet.careCount, 2)
        XCTAssertTrue(loaded.pet.isResting)
        XCTAssertEqual(loaded.pet.restingUntil, f.start.addingTimeInterval(240))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("pet-duck.json").path))
        for (index, companion) in existing.enumerated() {
            XCTAssertTrue(loaded.selectCompanion(companion))
            XCTAssertEqual(loaded.pet.hunger, Double(30 + index), companion.name)
        }
    }

    /// Renders every duck care context and verifies that only normal motion changes beats.
    /// A settled nap and the phase-independent wake/nuzzle poses also remain renderable.
    /// When requested, exports the native images for documentation and visual inspection.
    @MainActor
    func testPuddleCareScenesRenderWithAndWithoutReducedMotion() throws {
        let f = try CareFixture(); defer { f.clean() }
        let model = f.model()
        XCTAssertTrue(model.selectCompanion(.duck))
        let scenes: [(CareAction, ByteSprite.Mood)] = [(.meal, .eating), (.snack, .eating), (.water, .drinking),
            (.play, .happy), (.explore, .eating), (.rest, .sleeping), (.wake, .neutral), (.affection, .happy)]
        let phaseSensitiveActions: [CareAction] = [.meal, .snack, .water, .play, .explore]
        for (action, mood) in scenes {
            model.pet = PetState(now: f.start)
            if action == .wake { model.pet.restingUntil = f.start.addingTimeInterval(240) }
            let token = try XCTUnwrap(model.beginCare(action))
            if action == .rest {
                model.completeCare(token)
                XCTAssertTrue(model.pet.isResting, "The nest must also render after the care animation settles")
            }
            for reduced in [false, true] {
                var frames: [Data] = []
                for phase in 0...1 {
                    let scene = CareView(model: model, accent: Color(red: 0.88, green: 0.63, blue: 0.22),
                                         mood: mood, phase: phase, isBusy: true, onCare: { _ in })
                    let view = VStack(spacing: 8) {
                        Text(action.title(for: .duck)).font(.headline)
                        scene.habitat(reducingMotion: reduced)
                    }
                    .padding(16).frame(width: 370).background(Color(white: 0.97))
                    .environment(\.colorScheme, .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.cgImage, action.rawValue)
                    XCTAssertEqual(image.width, 740)
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    XCTAssertGreaterThan(data.count, 1000)
                    frames.append(data)
                    if phase == 1, let directory = ProcessInfo.processInfo.environment["NOOKLINGS_SNAPSHOT_DIRECTORY"] {
                        let url = URL(fileURLWithPath: directory)
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        try data.write(to: url.appendingPathComponent("duck-\(action.rawValue)\(reduced ? "-reduced-motion" : "").png"))
                    }
                }
                if phaseSensitiveActions.contains(action) {
                    if reduced {
                        XCTAssertEqual(frames[0], frames[1], "\(action.rawValue) must hold a fixed pose with Reduce Motion")
                    } else {
                        XCTAssertNotEqual(frames[0], frames[1], "\(action.rawValue) must change pose between animation beats")
                    }
                }
            }
            model.cancelCare(token)
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
