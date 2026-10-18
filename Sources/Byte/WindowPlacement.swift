import Foundation

enum WindowPlacement {
    /// Pick one real display, never the bounding union (which can include gaps).
    static func frame(anchor: CGPoint, size: CGSize, displays: [CGRect]) -> CGRect? {
        guard anchor.x.isFinite, anchor.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - anchor.x, 0, anchor.x - rect.maxX)
            let dy = max(rect.minY - anchor.y, 0, anchor.y - rect.maxY)
            return dx * dx + dy * dy
        }
        guard let screen = displays.filter({ $0.width > 0 && $0.height > 0 })
            .min(by: { distance($0) < distance($1) }) else { return nil }
        let width = min(max(1, size.width), screen.width), height = min(max(1, size.height), screen.height)
        return CGRect(x: min(max(anchor.x - width / 2, screen.minX), screen.maxX - width),
                      y: min(max(anchor.y - height, screen.minY), screen.maxY - height),
                      width: width, height: height)
    }
}
