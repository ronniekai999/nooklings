import Foundation

enum Quips {
    /// Short, local hatchling lines for Niblet's optional check-ins.
    static let lines = [
        "Rawr! (That's hello in dino.)",
        "Need a hand? Mine are tiny, but I'm all in.",
        "Thinking… tiny stomp… tiny stomp…",
        "Stomping through your context window.",
        "Digging up the answer — I'm good at fossils.",
        "Still growing into these tiny feet.",
        "Two tiny arms, one big brain.",
        "Just a nibble. I promise.",
        "Small arms. Huge enthusiasm.",
        "Stuck? Let's dig in together.",
        "Stomp. That was a thought.",
        "Keeping your notch from going extinct.",
        "Newly hatched. Extremely curious.",
        "T-rex-cellent to see you.",
        "Let's make today rawr-some."
    ]

    static func random() -> String { lines.randomElement()! }
}
