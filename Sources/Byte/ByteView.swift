import SwiftUI
import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
struct ByteView: View {
    @ObservedObject var model: ByteModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Idle + breach
    @State private var bob = false
    @State private var glowPulse = false
    @State private var breachOffset: CGFloat = 0
    @State private var breachScale: CGFloat = 1
    @State private var breachTilt: Double = 0
    @State private var swimX: CGFloat = 0
    @State private var isBusy = false
    @State private var lastMove = -1
    @State private var showHappy = false
    @AppStorage("byte.sounds", store: AppPreferences.shared) private var soundsOn = true
    @State private var rippleScale: CGFloat = 0.2
    @State private var rippleOpacity: Double = 0

    // Quip bubble (idle)
    @State private var quip: String? = nil
    @State private var quipID = 0

    @State private var hovering = false
    @State private var isDragging = false
    @State private var showCare = false
    @State private var careScene: CareAction?
    @State private var careTask: Task<Void, Never>?
    @State private var activeCareToken: UUID?
    @State private var carePhase = 0
    @State private var propX: CGFloat = 0
    @State private var propY: CGFloat = 0
    @State private var propScale: CGFloat = 1
    @State private var propOpacity: Double = 0
    @State private var propRotation: Double = 0
    // Hover action bar (quick feed/water/play without the big menu)
    @State private var showActions = false
    @State private var hoverBand = false
    @State private var hoverBar = false
    @State private var hideActionsTask: Task<Void, Never>? = nil
    @State private var dropTarget = false
    @FocusState private var inputFocused: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var secondsToNext = Int.random(in: 10...18)

    private var accent: Color {
        let c = model.companion.tint
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    private var mood: ByteSprite.Mood {
        if model.pet.isResting || careScene == .rest { return .sleeping }
        if careScene == .meal || careScene == .snack { return carePhase.isMultiple(of: 2) ? .happy : .eating }
        if careScene == .water { return carePhase.isMultiple(of: 2) ? .neutral : .drinking }
        if model.companion == .duck && careScene == .explore { return carePhase.isMultiple(of: 2) ? .thinking : .eating }
        if careScene == .play || careScene == .explore || careScene == .affection { return .happy }
        if model.isThinking || model.searching { return .thinking }
        if showHappy { return .happy }
        return model.pet.happiness >= 70 ? .happy : .neutral
    }

    private var needSymbol: String? {
        if model.pet.isResting { return "moon.zzz.fill" }
        if model.pet.hunger < 28 || model.pet.thirst < 28 || model.pet.energy < 25 || model.pet.happiness < 30 {
            return model.pet.suggestedAction.symbol
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 4) {
            band
            bubbleArea
            if !model.chatOpen { Spacer(minLength: 0) }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $dropTarget) { providers in
            handleDrop(providers)
        }
        .onAppear {
            startIdle()
            model.onCheckIn = { msg in checkIn(msg) }
        }
        .onReceive(tick) { _ in
            model.tickPet()                       // decay needs + maybe a check-in (continues during chat)
            guard !model.chatOpen, !showCare, !model.pet.isResting else { return }
            secondsToNext -= 1
            if secondsToNext <= 0 {
                secondsToNext = Int.random(in: 9...17)
                randomMove()
            }
        }
        .onDisappear {
            careTask?.cancel()
            if let token = activeCareToken { model.cancelCare(token) }
            hideActionsTask?.cancel()
            resetCareScene()
        }
        .onChange(of: reduceMotion) { _, _ in startIdle() }
        .onChange(of: model.companion) { _, _ in
            quip = nil; showHappy = false; secondsToNext = 12
        }
        .onChange(of: model.provider) { _, provider in
            if provider == .anthropic, model.hasKey, model.anthropicModelsCheckedAt == nil { model.reloadAnthropicModels() }
        }
        .onChange(of: model.chatOpen) { _, open in
            guard open else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                inputFocused = true
            }
        }
        .onChange(of: model.focusRequest) { _, _ in
            inputFocused = false
            Task { @MainActor in
                await Task.yield()
                inputFocused = true
            }
        }
    }

    private var band: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.50).opacity(glowPulse ? 0.30 : 0.15), .clear],
                                     center: .center, startRadius: 2, endRadius: 48))
                .frame(width: 130, height: 130)
                .offset(y: breachOffset)
                .blur(radius: 7)
                .allowsHitTesting(false)

            surface.offset(y: 32)

            Circle()
                .stroke(accent.opacity(rippleOpacity), lineWidth: 2)
                .frame(width: 54, height: 54)
                .scaleEffect(x: rippleScale, y: rippleScale * 0.4)
                .offset(y: 18)
                .allowsHitTesting(false)

            if model.companion == .duck && (model.pet.isResting || careScene == .rest) {
                PropSprite(prop: .nest, size: 66)
                    .offset(y: 32)
                    .allowsHitTesting(false)
            }

            ByteSprite(scale: 0.90, mood: mood, companion: model.companion)
                .scaleEffect(breachScale)
                .rotationEffect(.degrees(breachTilt))
                .offset(x: reduceMotion ? 0 : swimX, y: (bob && !reduceMotion && !model.pet.isResting ? 1.5 : 0) + breachOffset)
                .shadow(color: .black.opacity(0.30), radius: 5, y: 2)
                .shadow(color: .white.opacity(0.12), radius: 3)
                .scaleEffect(hovering ? 1.06 : 1.0)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !isDragging { isDragging = true; model.onDragBegan?() }
                            model.onDragChanged?(v.translation)
                        }
                        .onEnded { v in
                            isDragging = false
                            let moved = (v.translation.width * v.translation.width
                                       + v.translation.height * v.translation.height).squareRoot()
                            if moved < 6 { poke() } else { model.onDragEnded?() }
                        }
                )
                .onHover { h in
                    withAnimation(.easeOut(duration: 0.2)) { hovering = h }
                }
                .contextMenu {
                    Button(model.chatOpen ? "Close chat" : "Ask \(model.companion.name)…") { model.toggleChat() }
                    Button("Do a trick") { randomMove() }.disabled(model.pet.isResting || isBusy)
                    Button("Care for \(model.companion.name)…") { NSApp.activate(ignoringOtherApps: true); showCare = true }
                    if model.hasArchive {
                        Divider()
                        Button("Reopen last chat") {
                            model.reopenLastArchive()
                            if !model.chatOpen { model.toggleChat() }
                        }
                    }
                    if model.hasConnection || (model.provider == .chatGPT && model.chatGPT.isSignedIn) {
                        Divider()
                        Button("Sign out") { model.signOut() }
                    }
                    Divider()
                    Button("Reset position to notch") { model.onResetPosition?() }
                    Button("Quit Nooklings") { NSApp.terminate(nil) }
                }
                .help("Hover for actions · click to chat · drag to move")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.companion.name)
                .accessibilityHint("Opens or closes chat")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.toggleChat() }
                .accessibilityValue(model.pet.status)
                .accessibilityAction(named: Text("Open care")) { showCare = true }
                .focusable()
                .onKeyPress(keys: [.return, .space]) { _ in model.toggleChat(); return .handled }

            if let action = careScene, !(model.companion == .duck && action == .rest) {
                PropSprite(prop: .object(for: action, companion: model.companion), size: 30)
                    .scaleEffect(propScale)
                    .rotationEffect(.degrees(propRotation))
                    .opacity(propOpacity)
                    .offset(x: propX, y: propY)
                    .allowsHitTesting(false)
            }

            if !model.chatOpen, let symbol = needSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(6).background(.regularMaterial, in: Circle())
                    .offset(x: 48, y: -29)
                    .allowsHitTesting(false)
            }

        }
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hoverBand = $0; updateActions() }
        .overlay(alignment: .bottom) { actionBar }
        .popover(isPresented: $showCare, arrowEdge: .bottom) {
            CareView(model: model, accent: accent, mood: mood, phase: carePhase,
                     isBusy: isBusy, onCare: performCare)
        }
    }

    // MARK: - Hover action bar

    private var actionBar: some View {
        HStack(spacing: 3) {
            quickAction(.meal, label: "Feed")
            quickAction(.water, label: model.companion == .dolphin ? "Splash" : "Water")
            quickAction(.play, label: "Play")
            quickAction(model.pet.isResting ? .wake : .rest, label: model.pet.isResting ? "Wake" : "Rest")
            Button {
                NSApp.activate(ignoringOtherApps: true)
                showCare = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "pawprint.fill").font(.system(size: 13))
                    Text("Care").font(.system(size: 9, weight: .medium))
                }.frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Companions and care")
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .opacity(showActions && !model.chatOpen ? 1 : 0)
        .allowsHitTesting(showActions && !model.chatOpen)
        .onHover { hoverBar = $0; updateActions() }
        .offset(y: 13)
    }

    private func quickAction(_ action: CareAction, label: String) -> some View {
        Button { performCare(action) } label: {
            VStack(spacing: 3) {
                if action == .wake {
                    Image(systemName: "sun.max.fill").font(.system(size: 14))
                } else {
                    PropSprite(prop: .object(for: action, companion: model.companion), size: 17)
                }
                Text(label).font(.system(size: 9, weight: .medium))
            }.frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || model.activeCare != nil || model.pet.unavailableReason(for: action, companion: model.companion) != nil)
        .help(model.pet.unavailableReason(for: action, companion: model.companion) ?? action.title(for: model.companion))
        .accessibilityLabel(action.title(for: model.companion))
    }

    /// Show the bar while the band or the bar is hovered; hide shortly after both clear.
    /// The hide task re-checks at fire time so crossing from band to bar never dismisses it.
    private func updateActions() {
        if model.chatOpen { hoverBand = false; hoverBar = false }
        if hoverBand || hoverBar {
            hideActionsTask?.cancel(); hideActionsTask = nil
            if !showActions { withAnimation(.easeOut(duration: 0.15)) { showActions = true } }
        } else {
            hideActionsTask?.cancel()
            hideActionsTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                if !hoverBand && !hoverBar {
                    withAnimation(.easeOut(duration: 0.2)) { showActions = false }
                }
            }
        }
    }

    @ViewBuilder private var bubbleArea: some View {
        if model.chatOpen {
            ChatPanel(model: model, focused: $inputFocused, accent: accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16).padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        } else if let q = quip {
            SpeechBubble(text: q, accent: accent)
                .frame(width: 200)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.scale(scale: 0.7, anchor: .top).combined(with: .opacity))
                .id(quipID)
        }
    }

    private var surface: some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color.black.opacity(0.26), Color.black.opacity(0.10), .clear],
                                 center: .center, startRadius: 1, endRadius: 46))
            .frame(width: 104, height: 22)
            .allowsHitTesting(false)
    }

    // MARK: behaviour

    private func startIdle() {
        bob = false; glowPulse = false
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { bob = true }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { glowPulse = true }
    }

    private func poke() {
        if !reduceMotion && !model.pet.isResting {
            if model.companion == .duck { waddle() } else { breach() }
        }
        model.toggleChat()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isStreaming, AttachmentInput.load(providers, into: model) else { return false }
        model.openAndFocusChat()
        return true
    }

    // MARK: tricks

    /// Pick a random behaviour (skipping whatever ran last so it feels organic).
    private func randomMove() {
        guard !isBusy, !model.pet.isResting, model.activeCare == nil, !reduceMotion else { return }
        let moves: [() -> Void] = model.companion == .duck
            ? [waddle, wiggle, nod, greet]
            : [breach, swim, spin, wiggle, nod, dive, greet]
        var i = Int.random(in: 0..<moves.count)
        if i == lastMove { i = (i + 1) % moves.count }
        lastMove = i
        moves[i]()
    }

    /// Tiny alternating steps, with a happy peep at the end.
    private func waddle() {
        guard !isBusy else { return }
        isBusy = true; showHappy = true
        Task { @MainActor in
            for step in 0..<6 {
                guard !reduceMotion, model.companion == .duck else { break }
                withAnimation(.easeInOut(duration: 0.16)) {
                    swimX = step.isMultiple(of: 2) ? -7 : 7
                    breachTilt = step.isMultiple(of: 2) ? -7 : 7
                    breachOffset = step.isMultiple(of: 2) ? -2 : 0
                }
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
            withAnimation(.easeOut(duration: 0.2)) { swimX = 0; breachTilt = 0; breachOffset = 0 }
            if soundsOn && model.companion == .duck { SoundPlayer.shared.playCare(.affection, companion: .duck) }
            try? await Task.sleep(nanoseconds: 200_000_000)
            showHappy = false; isBusy = false
        }
    }

    private func breach() {
        guard !isBusy else { return }
        isBusy = true
        withAnimation(.easeOut(duration: 0.36)) {
            breachOffset = -40; breachScale = 1.12; breachTilt = -8
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeIn(duration: 0.5)) {
                breachOffset = 0; breachScale = 1.0; breachTilt = 0
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            puff()
            if soundsOn { SoundPlayer.shared.playCare(.play, companion: model.companion) }
            isBusy = false
        }
    }

    /// A quick dart to the side and back.
    private func swim() {
        guard !isBusy else { return }
        isBusy = true
        withAnimation(.easeInOut(duration: 0.34)) { swimX = -30; breachTilt = -5; breachOffset = -4 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { swimX = 16; breachTilt = 3 }
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.easeOut(duration: 0.42)) { swimX = 0; breachTilt = 0; breachOffset = 0 }
            try? await Task.sleep(nanoseconds: 440_000_000)
            isBusy = false
        }
    }

    /// A playful barrel roll.
    private func spin() {
        guard !isBusy else { return }
        isBusy = true
        withAnimation(.easeInOut(duration: 0.7)) { breachTilt = 360; breachScale = 1.08 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            breachTilt = 0                                   // 360° == 0°, so this is seamless
            withAnimation(.easeOut(duration: 0.25)) { breachScale = 1.0 }
            try? await Task.sleep(nanoseconds: 260_000_000)
            isBusy = false
        }
    }

    /// A happy side-to-side wiggle.
    private func wiggle() {
        guard !isBusy else { return }
        isBusy = true
        showHappy = true
        let seq: [(Double, UInt64)] = [(9, 120), (-9, 120), (6, 120), (-4, 100), (0, 130)]
        Task { @MainActor in
            for (t, d) in seq {
                withAnimation(.easeInOut(duration: Double(d) / 1000)) { breachTilt = t }
                try? await Task.sleep(nanoseconds: d * 1_000_000)
            }
            showHappy = false
            isBusy = false
        }
    }

    /// A small, friendly nod.
    private func nod() {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.18)) { breachOffset = 7; breachTilt = 4 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeInOut(duration: 0.18)) { breachOffset = -2; breachTilt = -1 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.2)) { breachOffset = 0; breachTilt = 0 }
            try? await Task.sleep(nanoseconds: 220_000_000)
            isBusy = false
        }
    }

    /// Crouch down and pop back up.
    private func dive() {
        guard !isBusy else { return }
        isBusy = true
        withAnimation(.easeIn(duration: 0.34)) { breachOffset = 26; breachScale = 0.9; breachTilt = 6 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            puff()
            if soundsOn { SoundPlayer.shared.playCare(.play, companion: model.companion) }
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.5)) { breachOffset = 0; breachScale = 1.0; breachTilt = 0 }
            try? await Task.sleep(nanoseconds: 520_000_000)
            isBusy = false
        }
    }

    /// A cheerful greeting: a happy quip with a little nod.
    private func greet() {
        guard !isBusy else { return }
        isBusy = true
        showHappy = true
        if !model.chatOpen { say(model.companion.greeting) }
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.18)) { breachOffset = 7; breachTilt = 4 }
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { breachOffset = 0; breachTilt = 0 }
            try? await Task.sleep(nanoseconds: 280_000_000)
            showHappy = false
            isBusy = false
        }
    }

    private func puff() {
        rippleScale = 0.2; rippleOpacity = 0.85
        withAnimation(.easeOut(duration: 0.6)) { rippleScale = 1.6; rippleOpacity = 0.0 }
    }

    // MARK: - Shared, cancellable care choreography

    private func performCare(_ action: CareAction) {
        guard !isBusy, let token = model.beginCare(action) else { return }
        isBusy = true; activeCareToken = token; careScene = action; carePhase = 0
        propOpacity = 1; propScale = 1; propRotation = 0
        propX = -52; propY = 23
        let companion = model.companion
        careTask = Task { @MainActor in
            defer { resetCareScene() }
            do {
                if reduceMotion {
                    // A static expression and brief feedback still complete every action.
                    carePhase = 1
                    try await pause(0.25)
                } else {
                    switch action {
                    case .meal, .snack:
                        withAnimation(.easeOut(duration: 0.4)) { propX = -35; propY = companion == .trex || companion == .dolphin ? -6 : 26 }
                        try await pause(0.4)
                        for bite in 1...4 {
                            carePhase = bite
                            withAnimation(.easeInOut(duration: 0.17)) {
                                if companion == .duck {
                                    applyDuckPose(action, phase: bite)
                                } else {
                                    breachOffset = bite.isMultiple(of: 2) ? 0 : 3
                                    propScale = CGFloat(max(0.15, 1 - Double(bite) * 0.20))
                                }
                            }
                            try await pause(0.22)
                        }
                        withAnimation(.easeOut(duration: 0.2)) { propOpacity = 0; breachOffset = 0 }
                    case .water:
                        propX = companion == .dolphin ? 0 : -35
                        propY = companion == .dolphin ? 8 : 33
                        for sip in 1...4 {
                            carePhase = sip
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if companion == .duck {
                                    applyDuckPose(action, phase: sip)
                                } else {
                                    breachOffset = companion == .dolphin ? (sip.isMultiple(of: 2) ? 0 : -9) : 2
                                    propScale = sip.isMultiple(of: 2) ? 1 : 1.2
                                }
                                propOpacity = sip.isMultiple(of: 2) ? 0.7 : 1
                            }
                            try await pause(0.3)
                        }
                    case .play, .explore:
                        try await animatePlay(companion, gentle: action == .explore)
                    case .rest:
                        propX = 45; propY = -25
                        withAnimation(.easeInOut(duration: 0.5)) {
                            switch companion {
                            case .trex: breachScale = 0.96; breachOffset = 4
                            case .dolphin: swimX = 8; breachTilt = 4
                            case .dog: breachScale = 0.97; breachTilt = 5
                            case .cat: breachScale = 0.94; breachOffset = 3
                            case .panda: breachOffset = 5; breachTilt = -3
                            case .duck: applyDuckPose(action, phase: 0)
                            }
                        }
                        try await pause(0.7)
                    case .wake:
                        propOpacity = 0
                        withAnimation(.easeOut(duration: 0.4)) {
                            if companion == .duck { applyDuckPose(action, phase: 0) }
                            else { breachOffset = -4 }
                        }
                        try await pause(0.4)
                    case .affection:
                        propX = -15; propY = -20
                        withAnimation(.easeOut(duration: 0.8)) {
                            propY = -40; propOpacity = 0
                            switch companion {
                            case .trex: breachTilt = -4; breachOffset = -2
                            case .dolphin: breachTilt = 8; swimX = 6
                            case .dog: breachTilt = 15; breachScale = 1.03
                            case .cat: breachTilt = -7; swimX = -3
                            case .panda: breachTilt = -3; breachOffset = 3
                            case .duck: applyDuckPose(action, phase: 0)
                            }
                        }
                        try await pause(0.8)
                    }
                }
                try Task.checkCancellation()
                model.completeCare(token)
                if soundsOn { SoundPlayer.shared.playCare(action, companion: companion) }
                if let feedback = model.careFeedback { say(feedback) }
                showHappy = action != .rest
                try await pause(reduceMotion ? 0.1 : 0.45)
            } catch {
                // Cancellation never awards food/play twice or leaves the UI locked.
                model.cancelCare(token)
            }
        }
    }

    private func animatePlay(_ companion: Companion, gentle: Bool) async throws {
        for beat in 0..<5 {
            carePhase = beat
            let up = beat.isMultiple(of: 2)
            withAnimation(.easeInOut(duration: 0.28)) {
                switch companion {
                case .trex:
                    propX = up ? -40 : 25; propY = 29
                    swimX = gentle ? (up ? -6 : 6) : (up ? -14 : 12)
                    breachOffset = gentle ? 0 : (up ? -8 : 0)
                    breachTilt = up ? -4 : 4
                case .dolphin:
                    propX = up ? -35 : 28; propY = gentle ? -20 : -6
                    swimX = up ? -18 : 18; breachOffset = up ? -18 : 3
                    breachTilt = up ? -18 : 14
                case .dog:
                    propX = up ? -64 : 16; propY = up ? -20 : 27
                    swimX = up ? -22 : 8; breachOffset = gentle ? 0 : (up ? -10 : 0)
                    breachTilt = up ? -3 : 3
                case .cat:
                    propX = up ? -48 : 10; propY = up ? -25 : 15
                    breachScale = up ? 0.95 : 1.04
                    swimX = up ? -5 : -15; breachOffset = gentle ? -2 : (up ? 4 : -14)
                case .panda:
                    propX = up ? -35 : 25; propY = 30
                    propRotation += 100
                    swimX = up ? -6 : 6; breachTilt = gentle ? 0 : (up ? -13 : 13)
                case .duck:
                    applyDuckPose(gentle ? .explore : .play, phase: beat)
                }
            }
            try await pause(0.3)
        }
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func applyDuckPose(_ action: CareAction, phase: Int) {
        let pose = DuckCarePose.frame(for: action, phase: phase)
        swimX = pose.x; breachOffset = pose.y; breachTilt = pose.tilt; breachScale = pose.scale
        propX = pose.propX; propY = pose.propY; propScale = pose.propScale; propRotation = pose.propTilt
    }

    private func resetCareScene() {
        careScene = nil; activeCareToken = nil; careTask = nil
        propOpacity = 0; propRotation = 0; carePhase = 0
        breachOffset = 0; breachScale = 1; breachTilt = 0; swimX = 0
        showHappy = false; isBusy = false
    }

    /// Byte speaking up on his own (need reminders / friendly hellos).
    private func checkIn(_ text: String) {
        guard !model.chatOpen, !showCare else { return }
        if !isBusy && !reduceMotion && !model.pet.isResting { greet() }
        say(text)
    }

    private func say(_ text: String) {
        guard !model.chatOpen else { return }
        quipID += 1
        let id = quipID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { quip = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if quipID == id {
                withAnimation(.easeIn(duration: 0.3)) { quip = nil }
            }
        }
    }
}

@MainActor
struct ChatPanel: View {
    @ObservedObject var model: ByteModel
    var focused: FocusState<Bool>.Binding
    let accent: Color

    @State private var dots = ""
    @State private var showSettings = false
    @State private var showArchives = false
    @State private var followsLatest = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dotTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let error = model.storageError {
                HStack(alignment: .top, spacing: 6) {
                    Text(error)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.storageError = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss save error")
                }
            }
            if let error = model.connectionError ?? (model.provider == .chatGPT ? model.chatGPT.error : nil) {
                Text(error)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.hasConnection {
                transcript
                if model.isPreparingImage {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Preparing image…").font(.caption)
                        Button("Cancel") { model.clearPendingImage() }
                    }
                }
                if let error = model.attachmentError {
                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if model.pendingImage != nil { pendingImageChip }
                ContextControls(model: model)
                inputBar
                if model.provider == .chatGPT {
                    HStack {
                        Text(model.chatGPTUsageBlocked ? "ChatGPT usage limit reached" :
                             model.isLoadingModels ? "Loading your models…" : "Using ChatGPT plan")
                        Spacer()
                        Link("Manage usage", destination: ChatGPTAuth.usageURL)
                        if model.chatGPTUsageBlocked {
                            Button("Try again") { model.retryChatGPTPlanUsage() }
                                .buttonStyle(.plain)
                        }
                    }
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                }
                if model.sessionInTok + model.sessionOutTok > 0 { costFooter }
            } else {
                signIn
            }
            HStack {
                Spacer()
                Menu {
                    Button("Larger chat") { model.onResizeChat?(CGSize(width: 100, height: 100)) }
                    Button("Smaller chat") { model.onResizeChat?(CGSize(width: -100, height: -100)) }
                } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Resize chat")
                .help("Resize chat here, or drag a window edge")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(accent.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .environment(\.openURL, OpenURLAction { url in
            WebLinks.canOpen(url) ? .systemAction : .discarded
        })
        .onPasteCommand(of: [.image]) { providers in
            if !model.isStreaming { AttachmentInput.load(providers, into: model) }
        }
        .onReceive(dotTimer) { _ in
            guard model.isThinking || model.searching else { if !dots.isEmpty { dots = "" }; return }
            dots = dots.count >= 3 ? "" : dots + "."
        }
        .alert("You're using your ChatGPT plan", isPresented: Binding(
            get: { model.chatGPT.showPlanWelcome }, set: { model.chatGPT.showPlanWelcome = $0 })) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Eligible AI requests in Nooklings use your ChatGPT plan or available credits. Review usage and set Nooklings’ limits in ChatGPT settings.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.companion.name).font(.system(size: 11, weight: .semibold, design: .rounded))
            Spacer()
            Text(model.model).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityLabel("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView(byte: model)
                }
            if model.hasArchive {
                Button { showArchives.toggle() } label: { Image(systemName: "tray.full") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Saved chats")
                    .accessibilityLabel("Saved chats")
                    .popover(isPresented: $showArchives, arrowEdge: .bottom) {
                        ArchivesView(model: model, accent: accent) { showArchives = false }
                    }
            }
            if !model.turns.isEmpty {
                Button { model.newChat() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("New chat (current one is saved)")
                    .accessibilityLabel("New chat")
                    .disabled(model.isStreaming)
            }
            Button { model.toggleChat() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Close chat")
        }
    }

    private var signIn: some View {
        ConnectionView(model: model)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.turns.isEmpty {
                        Text("Ask me anything — I'll keep it short, and I'll remember the thread 🦖")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.turns) { turn in
                        bubble(for: turn).id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 2)
                .background(ScrollPositionObserver { followsLatest = $0 })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if !followsLatest {
                    Button("Jump to latest") {
                        followsLatest = true
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }.buttonStyle(.bordered).padding(4)
                }
            }
            .onChange(of: model.turns.last?.text) {
                if followsLatest {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: model.turns.count) {
                if model.isStreaming && model.turns.last?.text.isEmpty == true { followsLatest = true }
                if followsLatest { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder private func bubble(for turn: ByteModel.Turn) -> some View {
        let isUser = turn.role == .user
        let isLast = turn.id == model.turns.last?.id
        let showThinking = !isUser && turn.text.isEmpty && (model.isThinking || model.searching)
        let statusLabel = model.searching ? "🔍 digging…" : "thinking"
        let showCursor = !isUser && model.isStreaming && isLast && !turn.text.isEmpty
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 28) }
            Group {
                if isUser {
                    VStack(alignment: .trailing, spacing: 5) {
                        if let img = turn.displayImage {
                            Image(nsImage: img)
                                .resizable().scaledToFit()
                                .frame(maxWidth: 180, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if turn.imageMissing {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                                HStack {
                                    Button("Locate image…") { AttachmentInput.choose(for: model, replacing: turn.id) }
                                    Button("Remove attachment") { model.removeMissingImage(from: turn.id) }
                                }.buttonStyle(.bordered).disabled(model.isStreaming || model.isPreparingImage)
                            }.font(.caption).accessibilityElement(children: .contain)
                        }
                        if !turn.text.isEmpty {
                            Text(turn.text)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                        }
                    }
                } else if showThinking {
                    Text("\(statusLabel)\(dots)")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        MarkdownText(text: turn.text + (showCursor ? " ▌" : ""))
                        if !turn.sources.isEmpty {
                            SourcesView(sources: turn.sources, accent: accent)
                        }
                        if let failure = turn.failure, !model.isStreaming || !isLast {
                            Text(failure)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? accent : Color.primary.opacity(0.08))
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .contextMenu { if !turn.text.isEmpty { Button("Copy") { copyText(turn.text) } } }
            if !isUser { Spacer(minLength: 28) }
        }
    }

    private func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Button { AttachmentInput.choose(for: model) } label: { Image(systemName: "paperclip") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Choose image file")
                .help("Choose an image file")
                .disabled(model.isStreaming || model.isPreparingImage)
            Button { pasteImage() } label: {
                Image(systemName: "doc.on.clipboard").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Paste an image from the clipboard")
            .accessibilityLabel("Paste image")
            .disabled(model.isStreaming)
            TextField("Ask \(model.companion.name)…", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .rounded))
                .focused(focused)
                .onSubmit { model.send() }
                .disabled(model.isStreaming)
            if model.isStreaming {
                Button { model.stopResponse() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .help("Stop reply")
                .accessibilityLabel("Stop reply")
            } else {
                Button { model.send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? accent : Color.secondary)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    private func pasteImage() {
        AttachmentInput.paste(into: model)
    }

    private var canSend: Bool {
        model.canSend && !model.isStreaming &&
        (!model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pendingImageB64 != nil)
    }

    private var pendingImageChip: some View {
        HStack(spacing: 8) {
            if let img = model.pendingImage {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text("Image attached — ask away")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            Button { model.clearPendingImage() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Remove attached image")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private var costFooter: some View {
        let toks = model.sessionInTok + model.sessionOutTok
        return HStack(spacing: 4) {
            if model.provider == .anthropic {
                Text(model.sessionCostIncomplete ? "Cost incomplete" : "≈ \(costString(model.sessionCost))")
                Text("·").foregroundStyle(.tertiary)
            }
            Text("\(tokString(toks)) tokens")
            if model.sessionSearches > 0 {
                Text("·").foregroundStyle(.tertiary)
                Text("\(model.sessionSearches) search\(model.sessionSearches == 1 ? "" : "es")")
            }
            Spacer()
            Text("this session").foregroundStyle(.tertiary)
        }
        .font(.system(size: 9, design: .rounded))
        .foregroundStyle(.secondary)
        .help(model.provider == .chatGPT ? "Token usage reported this session. Review plan and credit usage in ChatGPT settings."
              : "Estimated from token usage at approximate list prices — not exact billing.")
        .padding(.horizontal, 2)
    }

    private func costString(_ c: Double) -> String {
        c < 0.1 ? String(format: "$%.4f", c) : String(format: "$%.2f", c)
    }
    private func tokString(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

struct SpeechBubble: View {
    let text: String
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(.ultraThinMaterial)
                .frame(width: 14, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Lightweight markdown rendering

private enum MDBlock {
    case paragraph(String)
    case heading(Int, String)
    case bullets([String])
    case ordered([String])
    case code(String?, String)
}

/// Renders a useful subset of markdown — paragraphs (with **bold**, *italic*,
/// `inline code`, links), headings, bullet/numbered lists, and fenced code blocks
/// (monospaced, scrollable, with a copy button). Enough for Claude's replies in a
/// small bubble without pulling in a dependency.
@MainActor
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: MDBlock) -> some View {
        switch block {
        case .paragraph(let s):
            Text(inline(s))
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let level, let s):
            Text(inline(s))
                .font(.system(size: level <= 1 ? 15 : (level == 2 ? 13 : 12),
                              weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 14, design: .rounded)).foregroundStyle(.secondary)
                        Text(inline(items[i]))
                            .font(.system(size: 14, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).").font(.system(size: 14, design: .rounded)).foregroundStyle(.secondary)
                        Text(inline(items[i]))
                            .font(.system(size: 14, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .code(let lang, let code):
            CodeBlock(lang: lang, code: code)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        guard var a = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(s)
        }
        let codeRanges = a.runs.compactMap {
            ($0.inlinePresentationIntent?.contains(.code) == true) ? $0.range : nil
        }
        for r in codeRanges { a[r].font = .system(size: 12, design: .monospaced) }
        return a
    }

    private func blocks() -> [MDBlock] {
        var out: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var para: [String] = [], bullets: [String] = [], ordered: [String] = []
        func flushPara() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        func flushBullets() { if !bullets.isEmpty { out.append(.bullets(bullets)); bullets = [] } }
        func flushOrdered() { if !ordered.isEmpty { out.append(.ordered(ordered)); ordered = [] } }
        func flushAll() { flushPara(); flushBullets(); flushOrdered() }

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushAll()
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                out.append(.code(lang.isEmpty ? nil : lang, code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty { flushAll(); i += 1; continue }
            if line.hasPrefix("#") {
                flushAll()
                var lvl = 0
                var idx = line.startIndex
                while idx < line.endIndex, line[idx] == "#", lvl < 6 {
                    lvl += 1; idx = line.index(after: idx)
                }
                out.append(.heading(lvl, String(line[idx...]).trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushPara(); flushOrdered()
                bullets.append(String(line.dropFirst(2)))
                i += 1; continue
            }
            if let r = line.range(of: "^[0-9]+\\.\\s", options: .regularExpression) {
                flushPara(); flushBullets()
                ordered.append(String(line[r.upperBound...]))
                i += 1; continue
            }
            flushBullets(); flushOrdered()
            para.append(line)
            i += 1
        }
        flushAll()
        return out
    }
}

@MainActor
struct CodeBlock: View {
    let lang: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang ?? "code")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .help("Copy code")
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.30)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings (popover from the chat header)

@MainActor
struct ConnectionView: View {
    @ObservedObject var model: ByteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("AI connection", selection: Binding(get: { model.provider }, set: { model.selectProvider($0) })) {
                ForEach(ByteModel.AIProvider.allCases, id: \.self) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .disabled(model.isStreaming || model.isConnecting)
            if model.provider == .chatGPT {
                Text("Use your ChatGPT plan")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Eligible Plus and Pro users can use their plan or credits in Nooklings. Sign in securely in your browser; credentials stay in your Mac's Keychain.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.chatGPT.accounts.isEmpty {
                    Picker("Account", selection: Binding(
                        get: { model.chatGPT.activeClientID ?? "" },
                        set: { model.selectChatGPTAccount($0) })) {
                        ForEach(model.chatGPT.accounts) { account in
                            Text(account.label).tag(account.clientID)
                        }
                    }
                    .disabled(model.isStreaming || model.isConnecting || model.chatGPT.needsCredentialSave)
                }
                if model.chatGPT.needsCredentialSave {
                    Button("Retry Keychain save") { model.retryChatGPTCredentialSave() }
                        .disabled(model.isStreaming || model.isConnecting)
                }
                if model.isConnecting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                        if model.chatGPT.isSigningIn { Button("Cancel") { model.cancelChatGPTSignIn() } }
                    }
                } else {
                    Button("Continue with ChatGPT") { model.signInChatGPT() }
                        .disabled(model.isStreaming || model.chatGPT.needsCredentialSave)
                    if !model.chatGPT.accounts.isEmpty {
                        Button("Add ChatGPT account") { model.signInChatGPT(addAccount: true) }
                            .disabled(model.isStreaming || model.chatGPT.needsCredentialSave)
                    }
                }
                HStack {
                    Link("Manage usage", destination: ChatGPTAuth.usageURL)
                    Spacer()
                    if model.chatGPT.isSignedIn {
                        Button("Sign out") { model.signOut() }
                            .disabled(model.isConnecting)
                    }
                }
            } else {
                Text(model.hasKey ? "Claude API key connected" : "Connect your Anthropic API key")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Claude API usage uses your Anthropic account's API billing or eligible credits. Claude subscription sign-in for Nooklings requires Anthropic approval.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("sk-ant-…", text: $model.keyInput)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                    .padding(7).background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
                    .onSubmit { model.saveKey() }
                HStack {
                    Link("Get a key ↗", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    Spacer()
                    Button("Save") { model.saveKey() }
                        .disabled(model.keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.hasKey { Button("Remove key") { model.signOut() } }
                }
                .disabled(model.isStreaming)
            }
        }
        .font(.system(size: 11, design: .rounded))
        .controlSize(.small)
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var byte: ByteModel
    @AppStorage("byte.webSearch", store: AppPreferences.shared) private var webSearch = true
    @AppStorage("byte.sounds", store: AppPreferences.shared) private var sounds = true
    @AppStorage("byte.checkins", store: AppPreferences.shared) private var checkins = true
    @AppStorage("byte.puns", store: AppPreferences.shared) private var puns = 2
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { want in
            let service = SMAppService.mainApp
            do {
                if want {
                    if service.status != .enabled && service.status != .requiresApproval { try service.register() }
                } else if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
                loginError = nil
            } catch {
                loginError = "Couldn't change launch at login. \(error.localizedDescription)"
            }
            loginStatus = service.status
        })
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nooklings settings")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            ConnectionView(model: byte)
            Divider()

            Toggle("Web search", isOn: $webSearch).disabled(!byte.supportsWebSearch || byte.isStreaming)
            Toggle("Sound effects", isOn: $sounds)
            Toggle("Random check-ins", isOn: $checkins)
            ShortcutSettings(shortcut: byte.shortcut)
            Toggle("Launch at login", isOn: launchAtLogin)
            if loginStatus == .requiresApproval {
                Text("Allow Nooklings in Login Items to finish enabling launch at login.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let loginError {
                Text(loginError).foregroundStyle(.red)
                    .font(.system(size: 10, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Puns", selection: $puns) {
                Text("Off").tag(0)
                Text("Light").tag(1)
                Text("Lots").tag(2)
            }
            if byte.provider == .chatGPT {
                Picker("Model", selection: Binding(get: { byte.model }, set: { byte.selectChatGPTModel($0) })) {
                    if byte.chatGPTModels.isEmpty {
                        Text(byte.isLoadingModels ? "Loading models…" : "No models loaded").tag(byte.model)
                    }
                    ForEach(byte.chatGPTModels) { choice in Text(choice.display_name).tag(choice.slug) }
                }
                .disabled(byte.isStreaming || byte.isLoadingModels || byte.chatGPTModels.isEmpty)
                Button("Refresh models") { byte.reloadChatGPTModels() }
                    .disabled(byte.isStreaming || byte.isLoadingModels || !byte.chatGPT.canUsePlan)
            } else {
                ClaudeModelSettings(model: byte)
            }
            Divider()
            LimitSettings(limits: byte.limits, isClaude: byte.provider == .anthropic, spent: byte.dailyEstimatedCost)
            Divider()
            Button("Clean up unused images") { byte.cleanupImages() }
                .disabled(byte.isStreaming || byte.isPreparingImage)
            if let status = byte.imageCleanupStatus {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12, design: .rounded))
        .padding(14)
        }
        .frame(width: 340, height: 580)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }
}

// MARK: - Source links under web-search answers

@MainActor
struct SourcesView: View {
    let sources: [ByteModel.Turn.Source]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sources")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(Array(sources.prefix(6).enumerated()), id: \.offset) { i, s in
                Button {
                    if let u = URL(string: s.url), WebLinks.canOpen(u) {
                        NSWorkspace.shared.open(u)
                    }
                } label: {
                    Text("\(i + 1). \(label(for: s))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(s.url)
            }
        }
        .padding(.top, 2)
    }

    private func label(for s: ByteModel.Turn.Source) -> String {
        if !s.title.isEmpty, s.title != s.url { return s.title }
        return URL(string: s.url)?.host ?? s.url
    }
}

// MARK: - Saved-chats browser (popover from the chat header)

@MainActor
struct ArchivesView: View {
    @ObservedObject var model: ByteModel
    let accent: Color
    var onPick: () -> Void
    @State private var items: [ByteModel.ArchiveInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved chats")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if items.isEmpty {
                Text("No saved chats yet. Starting a new chat saves the current one here.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items) { it in
                            HStack(spacing: 6) {
                                Button {
                                    if model.reopenArchive(id: it.id) { onPick() }
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(it.preview)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("\(it.dateString) · \(it.count) msg")
                                            .font(.system(size: 9, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    model.deleteArchive(id: it.id)
                                    items = model.archiveList()
                                } label: {
                                    Image(systemName: "trash").font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Delete this saved chat")
                                .accessibilityLabel("Delete saved chat: \(it.preview)")
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { items = model.archiveList() }
    }
}
