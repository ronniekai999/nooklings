import AppKit
import SwiftUI

/// Listen to user scrolling, not content growth, so streamed tokens cannot turn
/// off following by themselves or pull a reader away from an older reply.
struct ScrollPositionObserver: NSViewRepresentable {
    var onUserScroll: (Bool) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.onUserScroll = onUserScroll }
    final class ObserverView: NSView {
        var onUserScroll: ((Bool) -> Void)?
        private var observation: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation); self.observation = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, let scroll = self.enclosingScrollView else { return }
                if let observation = self.observation { NotificationCenter.default.removeObserver(observation) }
                self.observation = NotificationCenter.default.addObserver(
                    forName: NSScrollView.didLiveScrollNotification, object: scroll, queue: .main
                ) { [weak self, weak scroll] _ in
                    guard let scroll, let document = scroll.documentView else { return }
                    self?.onUserScroll?(document.bounds.maxY - scroll.documentVisibleRect.maxY < 32)
                }
            }
        }
        deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    }
}
