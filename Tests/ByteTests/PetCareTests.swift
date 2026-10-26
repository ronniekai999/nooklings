import XCTest
@testable import Byte

final class PetCareTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testLegacySaveKeepsNeedsAndBirthday() throws {
        let legacy = """
        {"hunger":42,"thirst":61,"energy":23,"happiness":71,
         "lastTick":721692800,"lastCheckIn":721692799,"nextCheckIn":721694600,"born":720000000}
        """
        let pet = try JSONDecoder().decode(PetState.self, from: Data(legacy.utf8))
        XCTAssertEqual(pet.hunger, 42)
        XCTAssertEqual(pet.energy, 23)
        XCTAssertEqual(pet.born, Date(timeIntervalSinceReferenceDate: 720000000))
        XCTAssertEqual(pet.careCount, 0)
        XCTAssertNil(pet.restingUntil)
        let reloaded = try JSONDecoder().decode(PetState.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(reloaded.born, pet.born)
    }

    func testNapRecoversOverTimeAndContinuesAcrossRelaunch() throws {
        var pet = PetState(now: start)
        pet.energy = 20
        XCTAssertTrue(pet.perform(.rest, companion: .cat, at: start))
        XCTAssertEqual(pet.energy, 20, "Starting a nap must not award instant energy")
        pet.advance(to: start.addingTimeInterval(60), companion: .cat)
        XCTAssertEqual(pet.energy, 34, accuracy: 0.001)
        var reloaded = try JSONDecoder().decode(PetState.self, from: JSONEncoder().encode(pet))
        reloaded.advance(to: start.addingTimeInterval(240), companion: .cat)
        XCTAssertFalse(reloaded.isResting)
        XCTAssertEqual(reloaded.energy, 61.95, accuracy: 0.001, "Three minutes of sleep, then one minute awake")
    }

    func testWakeRetainsOnlyEnergyAlreadyRecovered() {
        var pet = PetState(now: start)
        pet.energy = 20
        pet.perform(.rest, companion: .trex, at: start)
        pet.perform(.wake, companion: .trex, at: start.addingTimeInterval(60))
        XCTAssertFalse(pet.isResting)
        XCTAssertEqual(pet.energy, 31, accuracy: 0.001)
        pet.advance(to: start.addingTimeInterval(120), companion: .trex)
        XCTAssertLessThan(pet.energy, 31)
    }

    func testClockRollbackCannotGrantDuplicateSleepEnergy() {
        var pet = PetState(now: start)
        pet.energy = 10
        pet.perform(.rest, companion: .dog, at: start)
        pet.advance(to: start.addingTimeInterval(60), companion: .dog)
        pet.advance(to: start.addingTimeInterval(30), companion: .dog)
        pet.advance(to: start.addingTimeInterval(60), companion: .dog)
        XCTAssertEqual(pet.energy, 20, accuracy: 0.001)
    }

    func testSleepingCompanionDoesNotEatOrPlay() {
        var pet = PetState(now: start)
        pet.energy = 30; pet.hunger = 30
        pet.perform(.rest, companion: .panda, at: start)
        XCTAssertFalse(pet.perform(.meal, companion: .panda, at: start))
        XCTAssertFalse(pet.perform(.play, companion: .panda, at: start))
        XCTAssertEqual(pet.hunger, 30)
        XCTAssertEqual(pet.careCount, 1)
    }

    /// Guards established species tuning and distinct game/refresh names as pets are added.
    func testFoodHydrationAndPlayHaveSpeciesSpecificEffects() {
        var dino = PetState(now: start), dolphin = PetState(now: start), panda = PetState(now: start)
        dino.hunger = 30; dolphin.hunger = 30; panda.hunger = 30
        dolphin.thirst = 40
        dino.perform(.meal, companion: .trex, at: start)
        dolphin.perform(.meal, companion: .dolphin, at: start)
        panda.perform(.meal, companion: .panda, at: start)
        XCTAssertEqual(dino.hunger, 68)
        XCTAssertEqual(dolphin.hunger, 62)
        XCTAssertEqual(dolphin.thirst, 48, "Fish contributes to Ripple's moisture")
        XCTAssertEqual(panda.hunger, 58)
        dino.perform(.play, companion: .trex, at: start)
        panda.perform(.play, companion: .panda, at: start)
        XCTAssertEqual(dino.energy, 62)
        XCTAssertEqual(panda.energy, 70)
        XCTAssertNotEqual(Companion.dolphin.hydrationLabel, Companion.dog.hydrationLabel)
        XCTAssertEqual(Set(Companion.allCases.map(\.game)).count, Companion.allCases.count)
        XCTAssertEqual(Set(Companion.allCases.map(\.hydrationAction)).count, Companion.allCases.count)
    }

    /// Exercises a complete duck routine, then reloads a nap to verify timed offline recovery.
    func testPuddleRoutineIncludesForagingAndOfflineNestRecovery() throws {
        var pet = PetState(now: start)
        pet.hunger = 30; pet.thirst = 30; pet.energy = 60; pet.happiness = 20
        XCTAssertTrue(pet.perform(.meal, companion: .duck, at: start))
        XCTAssertEqual(pet.hunger, 59)
        XCTAssertTrue(pet.perform(.snack, companion: .duck, at: start))
        XCTAssertEqual(pet.hunger, 72)
        XCTAssertTrue(pet.perform(.water, companion: .duck, at: start))
        XCTAssertEqual(pet.thirst, 65)
        XCTAssertEqual(pet.happiness, 41, "Bill rinses also make Puddle happy")
        XCTAssertTrue(pet.perform(.play, companion: .duck, at: start))
        XCTAssertEqual(pet.energy, 49)
        XCTAssertEqual(pet.thirst, 61)
        XCTAssertTrue(pet.perform(.explore, companion: .duck, at: start))
        XCTAssertEqual(pet.hunger, 78, "Duckweed foraging provides a small meal bonus")
        XCTAssertEqual(pet.happiness, 86)
        XCTAssertEqual(pet.energy, 43)
        XCTAssertTrue(pet.perform(.rest, companion: .duck, at: start))
        XCTAssertEqual(pet.energy, 43, "The nest does not award energy upfront")
        XCTAssertFalse(pet.perform(.explore, companion: .duck, at: start))
        var loaded = try JSONDecoder().decode(PetState.self, from: JSONEncoder().encode(pet))
        loaded.advance(to: start.addingTimeInterval(240), companion: .duck)
        XCTAssertFalse(loaded.isResting)
        XCTAssertEqual(loaded.energy, 91, accuracy: 0.001)
        XCTAssertEqual(loaded.careCount, 6)
        XCTAssertEqual(loaded.recentCare.first?.action, .rest)
    }

    /// Foraging must cap food/joy and respect need gates instead of becoming free care.
    func testDuckweedBonusIsBoundedAndStillRequiresEnoughEnergyAndWater() {
        var pet = PetState(now: start)
        pet.hunger = 99; pet.happiness = 97; pet.energy = 30; pet.thirst = 30
        XCTAssertTrue(pet.perform(.explore, companion: .duck, at: start))
        XCTAssertEqual(pet.hunger, 100)
        XCTAssertEqual(pet.happiness, 100)
        XCTAssertEqual(pet.energy, 24)
        pet.thirst = 19
        XCTAssertFalse(pet.perform(.explore, companion: .duck, at: start))
        pet.thirst = 40; pet.energy = 10
        XCTAssertFalse(pet.perform(.explore, companion: .duck, at: start))
        XCTAssertEqual(pet.careCount, 1)
    }

    func testNeedsGatePlayAndCapFood() {
        var pet = PetState(now: start)
        pet.energy = 10
        XCTAssertFalse(pet.perform(.play, companion: .dog, at: start))
        pet.energy = 80; pet.thirst = 10
        XCTAssertFalse(pet.perform(.explore, companion: .dog, at: start))
        pet.hunger = 89
        XCTAssertTrue(pet.perform(.meal, companion: .dog, at: start))
        XCTAssertEqual(pet.hunger, 100)
        XCTAssertFalse(pet.perform(.snack, companion: .dog, at: start))
    }

    func testOfflineDecayAndRestAreIndependentOfTickFrequency() {
        var once = PetState(now: start), often = PetState(now: start)
        once.energy = 20; often.energy = 20
        once.perform(.rest, companion: .panda, at: start)
        often.perform(.rest, companion: .panda, at: start)
        once.advance(to: start.addingTimeInterval(3600), companion: .panda)
        for second in 1...3600 { often.advance(to: start.addingTimeInterval(Double(second)), companion: .panda) }
        XCTAssertEqual(once.energy, often.energy, accuracy: 0.001)
        XCTAssertEqual(once.hunger, often.hunger, accuracy: 0.001)
        XCTAssertEqual(once.thirst, often.thirst, accuracy: 0.001)
        XCTAssertEqual(once.happiness, often.happiness, accuracy: 0.001)
    }

    func testJoyIsIndependentOfTicksAcrossNeedFloorsAndSleepCaps() {
        for companion in Companion.allCases {
            for sleeping in [false, true] {
                var once = PetState(now: start)
                once.hunger = 8; once.thirst = 18; once.energy = 94; once.happiness = 40
                if sleeping { once.perform(.rest, companion: companion, at: start) }
                var often = once
                once.advance(to: start.addingTimeInterval(48 * 3600), companion: companion)
                for minute in 1...(48 * 60) {
                    often.advance(to: start.addingTimeInterval(Double(minute) * 60), companion: companion)
                }
                XCTAssertEqual(once.happiness, often.happiness, accuracy: 0.000001, companion.name)
                XCTAssertEqual(once.energy, often.energy, accuracy: 0.000001)
                XCTAssertEqual(once.status, often.status)
            }
        }
    }

    func testCareHistoryIsBoundedAndPersists() throws {
        var pet = PetState(now: start)
        pet.happiness = 10
        for _ in 0..<8 { pet.perform(.affection, companion: .dog, at: start) }
        let loaded = try JSONDecoder().decode(PetState.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(loaded.careCount, 8)
        XCTAssertEqual(loaded.recentCare.count, 5)
        XCTAssertEqual(loaded.recentCare.first?.action, .affection)
    }

    /// Every declared animal and mood must decode to usable bundled artwork.
    func testEveryCompanionExpressionIsBundled() {
        for companion in Companion.allCases {
            for mood in ByteSprite.Mood.allCases {
                let image = CompanionArtwork.frame(companion, mood: mood)
                XCTAssertNotNil(image, "Missing \(companion.rawValue) / \(mood)")
                XCTAssertGreaterThan(image?.width ?? 0, 300)
                XCTAssertGreaterThan(image?.height ?? 0, 300)
            }
        }
    }
}
