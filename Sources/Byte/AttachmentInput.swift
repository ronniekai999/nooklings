import AppKit
import UniformTypeIdentifiers

@MainActor
enum AttachmentInput {
    static func choose(for model: ByteModel, replacing turnID: UUID? = nil) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.prompt = turnID == nil ? "Attach image" : "Use this image"
        picker.begin { [weak model] response in
            guard response == .OK, let url = picker.url else { return }
            Task { @MainActor in model?.attachImage(url: url, replacing: turnID) }
        }
    }

    static func paste(into model: ByteModel) {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = NSPasteboard.general.data(forType: type) { model.attachImage(data: data); return }
        }
        model.attachmentError = "The clipboard doesn't contain an image. Choose an image file instead."
    }

    @discardableResult
    static func load(_ providers: [NSItemProvider], into model: ByteModel) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: NSURL.self) { [weak model] value, _ in
                guard let url = value as? URL else { return }
                Task { @MainActor in model?.attachImage(url: url) }
            }
            return true
        }
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type) { [weak model] data, error in
            Task { @MainActor in
                if let data { model?.attachImage(data: data) }
                else { model?.attachmentError = error?.localizedDescription ?? "Couldn't read the dropped image." }
            }
        }
        return true
    }
}
