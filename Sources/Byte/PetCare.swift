import Foundation

struct CareEvent: Codable, Identifiable {
    var id = UUID()
    let action: CareAction
    let date: Date
}

/// Pure elapsed-time simulation. Legacy pet.json files decode without resetting Byte.
struct PetState: Codable {
    var hunger = 80.0
    var thirst = 80.0
    var energy = 80.0
    var happiness = 80.0
    var lastTick: Date
    var lastCheckIn: Date
    var nextCheckIn: Date
    var born: Date
    var restingUntil: Date?
    var careCount = 0
    var recentCare: [CareEvent] = []

    init(now: Date = Date()) {
        lastTick = now; lastCheckIn = now; born = now
        nextCheckIn = now.addingTimeInterval(1800)
    }

    enum CodingKeys: String, CodingKey {
        case hunger, thirst, energy, happiness, lastTick, lastCheckIn, nextCheckIn, born
        case restingUntil, careCount, recentCare
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required legacy fields distinguish a damaged save from a new companion.
        hunger = try c.decode(Double.self, forKey: .hunger)
        thirst = try c.decode(Double.self, forKey: .thirst)
        energy = try c.decode(Double.self, forKey: .energy)
        happiness = try c.decode(Double.self, forKey: .happiness)
        lastTick = try c.decode(Date.self, forKey: .lastTick)
        born = try c.decode(Date.self, forKey: .born)
        lastCheckIn = try c.decodeIfPresent(Date.self, forKey: .lastCheckIn) ?? lastTick
        nextCheckIn = try c.decodeIfPresent(Date.self, forKey: .nextCheckIn) ?? lastTick.addingTimeInterval(1800)
        restingUntil = try c.decodeIfPresent(Date.self, forKey: .restingUntil)
        careCount = max(0, try c.decodeIfPresent(Int.self, forKey: .careCount) ?? 0)
        recentCare = Array((try c.decodeIfPresent([CareEvent].self, forKey: .recentCare) ?? []).prefix(5))
        normalize()
    }

    var isResting: Bool { restingUntil != nil }
    var wellbeing: Double { (hunger + thirst + energy + happiness) / 4 }
    var status: String {
        if isResting { return "Resting" }
        if min(hunger, thirst, energy) < 28 { return "Needs a little care" }
        return happiness >= 70 ? "Happy & curious" : "Ready for some company"
    }

    var suggestedAction: CareAction {
        if isResting { return .wake }
        if thirst < 35 { return .water }
        if hunger < 35 { return .meal }
        if energy < 30 { return .rest }
        if happiness < 65 { return .explore }
        return .affection
    }

    mutating func advance(to now: Date, companion: Companion) {
        guard now > lastTick else { return } // A clock rollback must not duplicate recovery.
        let hours = now.timeIntervalSince(lastTick) / 3600
        let sleepSeconds = restingUntil.map { max(0, min(now, $0).timeIntervalSince(lastTick)) } ?? 0
        let awakeHours = max(0, hours - sleepSeconds / 3600)
        let decay = companion.decayPerHour
        hunger -= hours * decay.food
        thirst -= hours * decay.water
        energy = min(100, energy + sleepSeconds / 60 * companion.napGainPerMinute)
        energy -= awakeHours * decay.energy
        // Exponential settling avoids happiness changing faster with more frequent ticks.
        let target = (max(0, hunger) + max(0, thirst) + max(0, energy)) / 3
        happiness += (target - happiness) * (1 - exp(-hours * 0.6))
        if let end = restingUntil, now >= end { restingUntil = nil }
        lastTick = now
        normalize()
    }

    func unavailableReason(for action: CareAction, companion: Companion) -> String? {
        if action == .wake { return isResting ? nil : "Already awake" }
        if isResting { return "Wake \(companion.name) gently first" }
        switch action {
        case .meal, .snack: return hunger >= 90 ? "Feeling full — save this for later" : nil
        case .water: return thirst >= 92 ? "\(companion.hydrationLabel) is already topped up" : nil
        case .play, .explore:
            let cost = action == .play ? companion.playCost : 6
            if energy < cost + 5 { return "A little rest first" }
            if thirst < 20 { return "\(companion.hydrationAction) first" }
            if hunger < 15 { return "A meal first" }
            return nil
        case .rest: return energy >= 95 ? "Wide awake and full of energy" : nil
        case .affection: return happiness >= 98 ? "Feeling loved already" : nil
        case .wake: return nil
        }
    }

    /// Called once at the animation's payoff, never optimistically at its start.
    @discardableResult
    mutating func perform(_ action: CareAction, companion: Companion, at now: Date) -> Bool {
        advance(to: now, companion: companion)
        guard unavailableReason(for: action, companion: companion) == nil else { return false }
        switch action {
        case .meal:
            hunger += companion.mealGain; happiness += 6
            if companion == .dolphin { thirst += 8 } // Ripple also gets moisture from fish.
        case .snack: hunger += companion.snackGain; happiness += 8
        case .water: thirst += companion.waterGain; happiness += companion == .dolphin ? 8 : 4
        case .play: energy -= companion.playCost; thirst -= companion == .dolphin ? 2 : 6; happiness += companion.playJoy
        case .explore: energy -= 6; thirst -= 2; happiness += 16
        case .rest: restingUntil = now.addingTimeInterval(companion.napMinutes * 60)
        case .wake: restingUntil = nil
        case .affection: happiness += 8
        }
        normalize()
        if action != .wake { careCount += 1 }
        recentCare.insert(CareEvent(action: action, date: now), at: 0)
        recentCare = Array(recentCare.prefix(5))
        return true
    }

    private mutating func normalize() {
        func bounded(_ x: Double) -> Double { x.isFinite ? max(0, min(100, x)) : 80 }
        hunger = bounded(hunger); thirst = bounded(thirst)
        energy = bounded(energy); happiness = bounded(happiness)
    }
}
