import SwiftUI

/// Smooth, shaded care objects, shared by the scene and dashboard cards.
enum CareProp {
    case meat, fish, squid, dinner, biscuit, bamboo, apple
    case pool, splash, bowl, fountain, spring
    case target, hoop, ball, feather, log, scent, bubble, sunbeam, leaf, heart, moon

    static func food(for companion: Companion, snack: Bool) -> CareProp {
        switch companion {
        case .trex: return .meat
        case .dolphin: return snack ? .squid : .fish
        case .dog: return snack ? .biscuit : .dinner
        case .cat: return snack ? .dinner : .fish
        case .panda: return snack ? .apple : .bamboo
        }
    }
    static func hydration(for companion: Companion) -> CareProp {
        switch companion {
        case .trex: return .pool
        case .dolphin: return .splash
        case .dog: return .bowl
        case .cat: return .fountain
        case .panda: return .spring
        }
    }
    static func toy(for companion: Companion, gentle: Bool) -> CareProp {
        if gentle {
            switch companion {
            case .trex, .dog: return .scent
            case .dolphin: return .bubble
            case .cat: return .sunbeam
            case .panda: return .leaf
            }
        }
        switch companion {
        case .trex: return .target
        case .dolphin: return .hoop
        case .dog: return .ball
        case .cat: return .feather
        case .panda: return .log
        }
    }
    static func object(for action: CareAction, companion: Companion) -> CareProp {
        switch action {
        case .meal, .snack: return food(for: companion, snack: action == .snack)
        case .water: return hydration(for: companion)
        case .play, .explore: return toy(for: companion, gentle: action == .explore)
        case .rest, .wake: return .moon
        case .affection: return .heart
        }
    }
}

struct PropSprite: View {
    let prop: CareProp
    var size: CGFloat = 32
    var body: some View {
        artwork
            .frame(width: 40, height: 40)
            .scaleEffect(size / 40)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        switch prop {
        case .meat:
            ZStack {
                Capsule().fill(Color(red: 0.96, green: 0.87, blue: 0.69)).frame(width: 37, height: 8).rotationEffect(.degrees(-30))
                Ellipse().fill(LinearGradient(colors: [.orange.opacity(0.9), .brown], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 27, height: 21).rotationEffect(.degrees(-30))
                Capsule().fill(.white.opacity(0.35)).frame(width: 14, height: 3).offset(x: -2, y: -5).rotationEffect(.degrees(-30))
            }
        case .fish:
            symbol("fish.fill", colors: [.white, .cyan, .blue])
        case .squid:
            ZStack {
                Ellipse().fill(LinearGradient(colors: [.pink.opacity(0.7), .purple], startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 25).offset(y: -5)
                HStack(spacing: 2) {
                    ForEach(0..<4) { index in
                        Capsule().fill(.purple.opacity(0.8)).frame(width: 3, height: 12)
                            .rotationEffect(.degrees(Double(index) * 12 - 18))
                    }
                }.offset(y: 12)
            }
        case .dinner:
            ZStack {
                bowl
                HStack(spacing: 1) {
                    ForEach(0..<5) { _ in Circle().fill(.brown.gradient).frame(width: 5, height: 6) }
                }.offset(y: -2)
            }
        case .biscuit:
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [.orange.opacity(0.6), .brown], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 21).rotationEffect(.degrees(-20))
                Image(systemName: "pawprint.fill").font(.system(size: 12)).foregroundStyle(.brown.opacity(0.8))
            }
        case .bamboo, .log:
            HStack(spacing: 2) {
                ForEach(0..<3) { _ in
                    ZStack {
                        Capsule().fill(LinearGradient(colors: [.green, .mint, .green], startPoint: .leading, endPoint: .trailing)).frame(width: 7, height: 33)
                        VStack(spacing: 8) { ForEach(0..<3) { _ in Rectangle().fill(.black.opacity(0.25)).frame(width: 7, height: 1) } }
                    }
                }
            }.rotationEffect(.degrees(prop == .log ? 70 : 20))
        case .apple:
            ZStack {
                HStack(spacing: -8) {
                    Ellipse().fill(.red.gradient).frame(width: 19, height: 26)
                    Ellipse().fill(.red.gradient).frame(width: 19, height: 26)
                }.offset(y: 3)
                Capsule().fill(.brown).frame(width: 3, height: 9).rotationEffect(.degrees(14)).offset(y: -12)
                Ellipse().fill(.green.gradient).frame(width: 11, height: 5).rotationEffect(.degrees(-25)).offset(x: 6, y: -13)
            }
        case .pool, .spring:
            ZStack {
                Ellipse().fill(.gray.gradient).frame(width: 40, height: 19)
                Ellipse().fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)).frame(width: 33, height: 12).offset(y: -1)
                Ellipse().stroke(.white.opacity(0.6), lineWidth: 1).frame(width: 20, height: 5).offset(y: -2)
            }
        case .bowl, .fountain:
            ZStack {
                bowl
                Ellipse().fill(.cyan.gradient).frame(width: 28, height: 8).offset(y: -2)
                if prop == .fountain {
                    Capsule().fill(.cyan.gradient).frame(width: 4, height: 16).offset(y: -10)
                    Image(systemName: "drop.fill").font(.system(size: 9)).foregroundStyle(.cyan).offset(x: 7, y: -10)
                }
            }
        case .splash: symbol("water.waves", colors: [.white, .cyan, .blue])
        case .target:
            ZStack {
                Circle().fill(.orange.gradient).frame(width: 27, height: 27)
                Circle().stroke(.white.opacity(0.85), lineWidth: 3).frame(width: 17, height: 17)
                Circle().fill(.white).frame(width: 6, height: 6)
            }
        case .hoop: Circle().stroke(LinearGradient(colors: [.mint, .cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 6).frame(width: 30, height: 30)
        case .ball:
            ZStack {
                Circle().fill(RadialGradient(colors: [.yellow, .green], center: .topLeading, startRadius: 0, endRadius: 30)).frame(width: 29, height: 29)
                Capsule().stroke(.white.opacity(0.8), lineWidth: 2).frame(width: 15, height: 26).rotationEffect(.degrees(30))
            }
        case .feather:
            ZStack {
                Ellipse().fill(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
                    .frame(width: 13, height: 30).rotationEffect(.degrees(28))
                Capsule().fill(.white.opacity(0.8)).frame(width: 1.5, height: 37).rotationEffect(.degrees(28))
            }
        case .scent: symbol("pawprint.fill", colors: [.orange.opacity(0.6), .brown])
        case .bubble:
            Circle().fill(.cyan.opacity(0.12)).overlay(Circle().stroke(.cyan.opacity(0.8), lineWidth: 2))
                .overlay(Circle().fill(.white.opacity(0.9)).frame(width: 6, height: 6).offset(x: -5, y: -6)).frame(width: 27, height: 27)
        case .sunbeam: symbol("sun.max.fill", colors: [.yellow, .orange])
        case .leaf: symbol("leaf.fill", colors: [.mint, .green])
        case .heart: symbol("heart.fill", colors: [.pink, .red])
        case .moon: symbol("moon.stars.fill", colors: [.white, .indigo.opacity(0.6)])
        }
    }
    private var bowl: some View {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 3)
            .fill(LinearGradient(colors: [.white, Color(white: 0.65)], startPoint: .top, endPoint: .bottom))
            .frame(width: 34, height: 17).offset(y: 5)
    }
    private func symbol(_ name: String, colors: [Color]) -> some View {
        Image(systemName: name).font(.system(size: 29, weight: .medium))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
