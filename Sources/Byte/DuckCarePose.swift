import Foundation

/// One choreography shared by Puddle's notch scene and the larger care preview.
/// Coordinates use the notch sprite's scale; the dashboard scales them together.
struct DuckCarePose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var tilt: Double = 0
    var scale: CGFloat = 1
    var propX: CGFloat = 0
    var propY: CGFloat = 0
    var propScale: CGFloat = 1
    var propTilt: Double = 0

    static func frame(for action: CareAction, phase: Int) -> Self {
        let dip = !phase.isMultiple(of: 2)
        switch action {
        case .meal, .snack:
            return Self(x: -3, y: dip ? 3 : 0, tilt: dip ? -5 : 1,
                        propX: -23, propY: 29, propScale: max(0.25, 1 - CGFloat(phase) * 0.16))
        case .water:
            return Self(x: -3, y: dip ? 4 : -1, tilt: dip ? -6 : 2,
                        propX: -24, propY: 32, propScale: dip ? 1.18 : 1)
        case .play:
            return Self(x: dip ? -10 : 10, y: dip ? -3 : 0, tilt: dip ? -8 : 8,
                        propX: dip ? -34 : 23, propY: 30, propTilt: dip ? -12 : 12)
        case .explore:
            return Self(x: dip ? -8 : 3, y: dip ? 3 : 0, tilt: dip ? -7 : 3,
                        propX: -25, propY: 30, propScale: dip ? 0.85 : 1)
        case .rest:
            return Self(y: 5, scale: 0.96, propY: 32, propScale: 2.2)
        case .wake:
            return Self(y: -4, tilt: -3, propY: 32, propScale: 2.2)
        case .affection:
            return Self(x: -3, y: 1, tilt: -9, scale: 1.03, propX: -19, propY: -30)
        }
    }
}
