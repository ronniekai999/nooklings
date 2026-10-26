import Foundation

/// Stable identifiers also name each companion's artwork and independent save file.
enum Companion: String, Codable, CaseIterable, Identifiable {
    case trex, dolphin, dog, cat, panda, duck
    var id: String { rawValue }

    var name: String {
        switch self {
        case .trex: return "Byte"
        case .dolphin: return "Ripple"
        case .dog: return "Biscuit"
        case .cat: return "Miso"
        case .panda: return "Bao"
        case .duck: return "Puddle"
        }
    }

    var species: String {
        switch self {
        case .trex: return "T-Rex"
        case .dolphin: return "Dolphin"
        case .dog: return "Golden retriever"
        case .cat: return "Tabby cat"
        case .panda: return "Giant panda"
        case .duck: return "Pekin duckling"
        }
    }

    var personality: String {
        switch self {
        case .trex: return "Small arms. Big heart."
        case .dolphin: return "A little wave of wonder."
        case .dog: return "Your golden-hour best friend."
        case .cat: return "Curiosity, with a side of mischief."
        case .panda: return "Slow mornings. Happy tumbles."
        case .duck: return "Tiny waddles. Big feelings."
        }
    }

    var greeting: String {
        switch self {
        case .trex: return Quips.random()
        case .dolphin: return "Making a little splash in your day."
        case .dog: return "You’re here! That’s my favorite part."
        case .cat: return "I saved you a spot in my sunbeam."
        case .panda: return "One thing at a time. Then a bamboo break."
        case .duck: return "Peep! I saved the nicest puddle for you."
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
        case .duck: return (0.88, 0.63, 0.22)
        }
    }

    var meal: String {
        switch self {
        case .trex: return "Prime bites"
        case .dolphin: return "Fish school"
        case .dog: return "Dinner bowl"
        case .cat: return "Salmon supper"
        case .panda: return "Bamboo buffet"
        case .duck: return "Duckling crumble"
        }
    }

    var snack: String {
        switch self {
        case .trex: return "Turkey morsels"
        case .dolphin: return "Squid snack"
        case .dog: return "Crunchy biscuit"
        case .cat: return "Chicken nibbles"
        case .panda: return "Apple slices"
        case .duck: return "Pea nibbles"
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
        case .duck: return "Bill dip & splash"
        }
    }
    var hydrationHint: String {
        switch self {
        case .dolphin: return "A refreshing splash for Ripple’s skin."
        case .duck: return "Clean fresh water for little sips and a happy bill rinse."
        default: return "Fresh water and a quiet moment."
        }
    }

    var game: String {
        switch self {
        case .trex: return "Stomp chase"
        case .dolphin: return "Hoop dive"
        case .dog: return "Fetch"
        case .cat: return "Feather pounce"
        case .panda: return "Bamboo roll"
        case .duck: return "Lily-pad paddle"
        }
    }
    var gentleGame: String {
        switch self {
        case .trex: return "Scent trail"
        case .dolphin: return "Bubble chase"
        case .dog: return "Sniff safari"
        case .cat: return "Sunbeam chase"
        case .panda: return "Leaf puzzle"
        case .duck: return "Duckweed hunt"
        }
    }
    var restLabel: String {
        switch self {
        case .trex: return "Nest nap"
        case .dolphin: return "Quiet drift"
        case .dog: return "Cozy nap"
        case .cat: return "Catnap"
        case .panda: return "Bamboo snooze"
        case .duck: return "Reed-nest snooze"
        }
    }

    /// Care tuning follows the stable `allCases` order; gains are capped by `PetState`.
    var mealGain: Double { [38, 32, 34, 30, 28, 29][index] }
    var snackGain: Double { [16, 15, 12, 14, 12, 13][index] }
    var waterGain: Double { [42, 34, 40, 36, 38, 35][index] }
    var playCost: Double { [18, 15, 14, 12, 10, 11][index] }
    var playJoy: Double { [30, 32, 30, 28, 26, 29][index] }
    var napMinutes: Double { [5, 4, 5, 3, 6, 4][index] }
    var napGainPerMinute: Double { [11, 10, 10, 14, 9, 12][index] }
    /// Fullness earned by exploration; only Puddle's duckweed hunt provides food.
    var forageGain: Double { self == .duck ? 6 : 0 }
    var waterJoy: Double {
        switch self {
        case .dolphin: return 8
        case .duck: return 7
        default: return 4
        }
    }
    var playWaterCost: Double {
        switch self {
        case .dolphin: return 2
        case .duck: return 4
        default: return 6
        }
    }
    var decayPerHour: (food: Double, water: Double, energy: Double) {
        switch self {
        case .trex: return (8, 10, 3.5)
        case .dolphin: return (9, 8, 4)
        case .dog: return (7, 11, 4)
        case .cat: return (6, 9, 3)
        case .panda: return (10, 8, 2.5)
        case .duck: return (8.5, 9.5, 3.25)
        }
    }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
}

enum CareAction: String, CaseIterable, Codable, Identifiable {
    case meal, snack, water, play, explore, rest, wake, affection
    var id: String { rawValue }

    /// The selected animal's routine name, shared by controls, history, and reminders.
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
            case .duck: return "Cheek nuzzle"
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

    /// Describes nominal gains and costs before need caps or unavailable-action checks.
    func detail(for companion: Companion) -> String {
        switch self {
        case .meal: return "+\(Int(companion.mealGain)) fullness"
        case .snack: return "+\(Int(companion.snackGain)) fullness · a little treat"
        case .water: return "+\(Int(companion.waterGain)) \(companion.hydrationLabel.lowercased())"
        case .play: return "+\(Int(companion.playJoy)) joy · −\(Int(companion.playCost)) energy"
        case .explore:
            return companion.forageGain > 0
                ? "+16 joy · +\(Int(companion.forageGain)) fullness · −6 energy"
                : "+16 joy · −6 energy"
        case .rest: return "\(Int(companion.napMinutes)) min · energy recovers over time"
        case .wake: return "Keep the energy recovered so far"
        case .affection: return "+8 joy · a little time together"
        }
    }
}
