import AppKit
import Carbon
import SwiftUI

struct ShortcutSpec: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let standard = ShortcutSpec(keyCode: UInt32(kVK_Space),
                                       modifiers: UInt32(controlKey | optionKey), keyLabel: "Space")
    var isValid: Bool { keyCode < 128 && modifiers & UInt32(cmdKey | controlKey) != 0 }
    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }
    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var flags: UInt32 = 0
        for (native, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey),
                                 (.option, optionKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(native) { flags |= UInt32(carbon) }
        }
        modifiers = flags
        keyLabel = Int(event.keyCode) == kVK_Space ? "Space" :
            Int(event.keyCode) == kVK_Return ? "Return" : (event.charactersIgnoringModifiers ?? "Key \(event.keyCode)").uppercased()
    }
}

/// Register only the chosen key combination. No event tap, clipboard read, or
/// Accessibility permission is needed to open chat.
@MainActor
final class GlobalShortcut: ObservableObject {
    @Published private(set) var configuration: ShortcutSpec?
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if defaults.bool(forKey: "byte.shortcut.disabled") { configuration = nil }
        else if let data = defaults.data(forKey: "byte.shortcut"),
                let saved = try? JSONDecoder().decode(ShortcutSpec.self, from: data), saved.isValid {
            configuration = saved
        } else { configuration = .standard }
    }

    func start(action: @escaping () -> Void) {
        self.action = action
        guard handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak controller] in controller?.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { error = "Couldn't enable the chat shortcut (\(status))."; return }
        if let configuration, register(configuration) != noErr {
            error = "The chat shortcut is unavailable. Choose another combination in Settings."
        }
    }

    @discardableResult
    func set(_ next: ShortcutSpec?) -> Bool {
        if let next, !next.isValid {
            error = "Include Command or Control in your shortcut."; return false
        }
        let previous = configuration
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if handler != nil, let next, register(next) != noErr {
            if let previous { _ = register(previous) }
            error = "That shortcut is already in use or reserved by macOS. Try another combination."
            return false
        }
        configuration = next; error = nil
        defaults.set(next == nil, forKey: "byte.shortcut.disabled")
        if let next { defaults.set(try? JSONEncoder().encode(next), forKey: "byte.shortcut") }
        return true
    }

    private func register(_ spec: ShortcutSpec) -> OSStatus {
        RegisterEventHotKey(spec.keyCode, spec.modifiers,
                           EventHotKeyID(signature: 0x4E4F4F4B, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        action = nil
    }
}

@MainActor
struct ShortcutSettings: View {
    @ObservedObject var shortcut: GlobalShortcut
    @State private var recording = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Global chat shortcut", isOn: Binding(get: { shortcut.configuration != nil },
                set: { _ = shortcut.set($0 ? .standard : nil); recording = false }))
            if shortcut.configuration != nil {
                Button(recording ? "Press a shortcut… (Esc to cancel)" : "Change shortcut: \(shortcut.configuration!.label)") {
                    recording = true
                }
                .accessibilityHint("Press a key with Command or Control to open and focus chat from any app")
                if recording {
                    ShortcutRecorder(onKey: { if shortcut.set($0) { recording = false } },
                                     onCancel: { recording = false }).frame(height: 1)
                }
            }
            if let error = shortcut.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    var onKey: (ShortcutSpec) -> Void
    var onCancel: () -> Void
    func makeNSView(context: Context) -> Recorder { Recorder() }
    func updateNSView(_ view: Recorder, context: Context) {
        view.onKey = onKey; view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
    final class Recorder: NSView {
        var onKey: ((ShortcutSpec) -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if Int(event.keyCode) == kVK_Escape { onCancel?() }
            else { onKey?(ShortcutSpec(event: event)) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event); return true
        }
    }
}
