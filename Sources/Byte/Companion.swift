import Foundation

/// Stable identifiers also name each companion's artwork and independent save file.
enum Companion: String, Codable, CaseIterable, Identifiable {
    case trex, dolphin, dog, cat, panda
    var id: String { rawValue }

    var name: String {
        switch self {
        case .trex: return "Byte"
        case .dolphin: return "Ripple"
        case .dog: return "Biscuit"
        case .cat: return "Miso"
        case .panda: return "Bao"
        }
    }

    var species: String {
        switch self {
        case .trex: return "T-Rex"
        case .dolphin: return "Dolphin"
        case .dog: return "Golden retriever"
        case .cat: return "Tabby cat"
        case .panda: return "Giant panda"
        }
    }

    var personality: String {
        switch self {
        case .trex: return "Small arms. Big heart."
        case .dolphin: return "A little wave of wonder."
        case .dog: return "Your golden-hour best friend."
        case .cat: return "Curiosity, with a side of mischief."
        case .panda: return "Slow mornings. Happy tumbles."
        }
    }

    var greeting: String {
        switch self {
        case .trex: return Quips.random()
        case .dolphin: return "Making a little splash in your day."
        case .dog: return "You’re here! That’s my favorite part."
        case .cat: return "I saved you a spot in my sunbeam."
        case .panda: return "One thing at a time. Then a bamboo break."
        }
    }

    // RGB components keep the care model independent of SwiftUI.
    var tint: (Double, Double, Double) {
        switch self {
        case .trex: return (0.46, 0.72, 0.50)
        case .dolphin: return (0.28, 0.68, 0.88)
        case .dog: return (0.91, 0.63, 0.32)
        case .cat: return (0.85, 0.49, 0.40)
        case .panda: return (0.54, 0.71, 0.49)
        }
    }

    var meal: String {
        switch self {
        case .trex: return "Prime bites"
        case .dolphin: return "Fish school"
        case .dog: return "Dinner bowl"
        case .cat: return "Salmon supper"
        case .panda: return "Bamboo buffet"
        }
    }

    var snack: String {
        switch self {
        case .trex: return "Turkey morsels"
        case .dolphin: return "Squid snack"
        case .dog: return "Crunchy biscuit"
        case .cat: return "Chicken nibbles"
        case .panda: return "Apple slices"
        }
    }

    var hydrationLabel: String { self == .dolphin ? "Freshness" : "Hydration" }
    var hydrationAction: String {
        switch self {
        case .trex: return "Watering hole"
        case .dolphin: return "Splash refresh"
        case .dog: return "Refill bowl"
        case .cat: return "Fresh fountain"
        case .panda: return "Forest spring"
        }
    }
    var hydrationHint: String {
        self == .dolphin ? "A refreshing splash for Ripple’s skin." : "Fresh water and a quiet moment."
    }

    var game: String {
        switch self {
        case .trex: return "Stomp chase"
        case .dolphin: return "Hoop dive"
        case .dog: return "Fetch"
        case .cat: return "Feather pounce"
        case .panda: return "Bamboo roll"
        }
    }
    var gentleGame: String {
        switch self {
        case .trex: return "Scent trail"
        case .dolphin: return "Bubble chase"
        case .dog: return "Sniff safari"
        case .cat: return "Sunbeam chase"
        case .panda: return "Leaf puzzle"
        }
    }
    var restLabel: String {
        switch self {
        case .trex: return "Nest nap"
        case .dolphin: return "Quiet drift"
        case .dog: return "Cozy nap"
        case .cat: return "Catnap"
        case .panda: return "Bamboo snooze"
        }
    }

    var mealGain: Double { [38, 32, 34, 30, 28][index] }
    var snackGain: Double { [16, 15, 12, 14, 12][index] }
    var waterGain: Double { [42, 34, 40, 36, 38][index] }
    var playCost: Double { [18, 15, 14, 12, 10][index] }
    var playJoy: Double { [30, 32, 30, 28, 26][index] }
    var napMinutes: Double { [5, 4, 5, 3, 6][index] }
    var napGainPerMinute: Double { [11, 10, 10, 14, 9][index] }
    var decayPerHour: (food: Double, water: Double, energy: Double) {
        switch self {
        case .trex: return (8, 10, 3.5)
        case .dolphin: return (9, 8, 4)
        case .dog: return (7, 11, 4)
        case .cat: return (6, 9, 3)
        case .panda: return (10, 8, 2.5)
        }
    }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
}

enum CareAction: String, CaseIterable, Codable, Identifiable {
    case meal, snack, water, play, explore, rest, wake, affection
    var id: String { rawValue }

    func title(for companion: Companion) -> String {
        switch self {
        case .meal: return companion.meal
        case .snack: return companion.snack
        case .water: return companion.hydrationAction
        case .play: return companion.game
        case .explore: return companion.gentleGame
        case .rest: return companion.restLabel
        case .wake: return "Wake gently"
        case .affection:
            switch companion {
            case .trex: return "Chin scritches"
            case .dolphin: return "Say hello"
            case .dog: return "Belly rub"
            case .cat: return "Chin rub"
            case .panda: return "Gentle pat"
            }
        }
    }

    var symbol: String {
        switch self {
        case .meal, .snack: return "fork.knife"
        case .water: return "drop.fill"
        case .play: return "tennisball.fill"
        case .explore: return "sparkles"
        case .rest: return "moon.stars.fill"
        case .wake: return "sun.max.fill"
        case .affection: return "heart.fill"
        }
    }

    func detail(for companion: Companion) -> String {
        switch self {
        case .meal: return "+\(Int(companion.mealGain)) fullness"
        case .snack: return "+\(Int(companion.snackGain)) fullness · a little treat"
        case .water: return "+\(Int(companion.waterGain)) \(companion.hydrationLabel.lowercased())"
        case .play: return "+\(Int(companion.playJoy)) joy · −\(Int(companion.playCost)) energy"
        case .explore: return "+16 joy · −6 energy"
        case .rest: return "\(Int(companion.napMinutes)) min · energy recovers over time"
        case .wake: return "Keep the energy recovered so far"
        case .affection: return "+8 joy · a little time together"
        }
    }
}
