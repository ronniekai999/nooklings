import SwiftUI

@MainActor
struct CareView: View {
    @ObservedObject var model: ByteModel
    let accent: Color
    let mood: ByteSprite.Mood
    let phase: Int
    let isBusy: Bool
    let onCare: (CareAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private let sceneScale: CGFloat = 1.32 / 0.90
    /// Uses the active duck routine, or its ongoing nap, to place the preview.
    /// A fixed beat preserves the scene under Reduce Motion; other pets return nil.
    private func duckPose(reducingMotion: Bool) -> DuckCarePose? {
        guard model.companion == .duck,
              let action = model.activeCare ?? (model.pet.isResting ? .rest : nil) else { return nil }
        return DuckCarePose.frame(for: action, phase: reducingMotion ? 1 : phase)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Nooklings · Care", systemImage: "pawprint.fill")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close care")
            }.padding(16)
            Divider()
            ScrollView { dashboardContent }
        }
        .frame(width: 370, height: 620)
        .background(.regularMaterial)
    }

    /// The same content is rendered by CI without the AppKit scroll container.
    var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            companions
            habitat
            if let error = model.storageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                NeedMeter(label: "Fullness", symbol: "fork.knife", value: model.pet.hunger, accent: accent)
                NeedMeter(label: model.companion.hydrationLabel, symbol: "drop.fill", value: model.pet.thirst, accent: accent)
                NeedMeter(label: "Energy", symbol: "bolt.fill", value: model.pet.energy, accent: accent)
                NeedMeter(label: "Joy", symbol: "heart.fill", value: model.pet.happiness, accent: accent)
            }
            if model.pet.isResting { restProgress }
            feedback
            VStack(alignment: .leading, spacing: 8) {
                Text("ON THE MENU").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(1)
                LazyVGrid(columns: columns, spacing: 8) {
                    actionCard(.meal)
                    actionCard(.snack)
                }
                actionCard(.water)
                Text(model.companion.hydrationHint)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("TIME TOGETHER").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(1)
                LazyVGrid(columns: columns, spacing: 8) {
                    actionCard(.play)
                    actionCard(.explore)
                    actionCard(model.pet.isResting ? .wake : .rest)
                    actionCard(.affection)
                }
            }
            if !model.pet.recentCare.isEmpty { recentActivity }
        }
        .padding(16)
    }

    private var companions: some View {
        VStack(alignment: .leading, spacing: 7) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Companion.allCases) { companion in
                    Button { _ = model.selectCompanion(companion) } label: {
                        VStack(spacing: 3) {
                            ByteSprite(scale: 0.44, companion: companion)
                                .accessibilityHidden(true)
                                .frame(height: 43)
                            Text(companion.name).font(.system(size: 10, weight: .semibold))
                            Circle().fill(companion == model.companion ? accent : .clear).frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(companion == model.companion ? accent.opacity(0.15) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || model.isStreaming)
                    .help("\(companion.name) · \(companion.species)")
                    .accessibilityLabel("Choose \(companion.name), \(companion.species)")
                    .accessibilityValue(companion == model.companion ? "Selected" : "")
                }
            }
            Text(model.isStreaming ? "Finish the current reply to switch companions." : "Each friend keeps their own care history.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    var habitat: some View {
        habitat(reducingMotion: reduceMotion)
    }

    /// Renders the selected companion's habitat, expression, and active care object.
    /// The explicit motion policy also lets native previews exercise the read-only setting.
    func habitat(reducingMotion reduceMotion: Bool) -> some View {
        let duckPose = self.duckPose(reducingMotion: reduceMotion)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [accent.opacity(0.23), accent.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.companion.name).font(.system(size: 26, weight: .bold, design: .rounded))
                    Spacer()
                    Label(model.pet.status, systemImage: model.pet.isResting ? "moon.fill" : "heart.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(model.companion.species + " · " + (model.petAgeDays == 0 ? "Your new friend" : "Day \(model.petAgeDays + 1) together"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                ZStack {
                    if model.companion == .duck && model.activeCare != .wake && (model.pet.isResting || model.activeCare == .rest) {
                        PropSprite(prop: .nest, size: 66 * sceneScale)
                            .offset(y: 24 * sceneScale)
                    }
                    ByteSprite(scale: 1.32, mood: mood, companion: model.companion)
                        .scaleEffect(duckPose?.scale ?? (!reduceMotion && model.activeCare == .play && !phase.isMultiple(of: 2) ? 1.03 : 1))
                        .rotationEffect(.degrees(duckPose?.tilt ?? 0))
                        .offset(x: (duckPose?.x ?? 0) * sceneScale,
                                y: (duckPose?.y ?? 0) * sceneScale)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: phase)
                    if let action = model.activeCare, !(model.companion == .duck && action == .rest) {
                        let point = CarePropPlacement.point(for: action, companion: model.companion)
                        let bob: CGFloat = !reduceMotion && phase.isMultiple(of: 2) ? 8 : 0
                        PropSprite(prop: .object(for: action, companion: model.companion), size: duckPose == nil ? 34 : 30 * sceneScale)
                            .scaleEffect(duckPose?.propScale ?? 1)
                            .rotationEffect(.degrees(duckPose?.propTilt ?? 0))
                            .offset(x: duckPose.map { $0.propX * sceneScale } ?? point.map { $0.x * sceneScale } ?? -58,
                                    y: duckPose.map { $0.propY * sceneScale } ?? point.map { $0.y * sceneScale + bob } ?? (30 + bob))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: phase)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 156)
                HStack {
                    Text(model.companion.personality).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(model.pet.careCount == 1 ? "1 care moment" : "\(model.pet.careCount) care moments").lineLimit(1)
                }.font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }.padding(14)
        }
        .frame(height: 256)
        .accessibilityElement(children: .combine)
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.careFeedback ?? "\(model.companion.name) is ready for a little time with you.")
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            if !isBusy && !model.pet.isResting {
                Button { onCare(model.pet.suggestedAction) } label: {
                    Label(model.pet.suggestedAction.title(for: model.companion), systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(model.pet.unavailableReason(for: model.pet.suggestedAction, companion: model.companion) != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var restProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(model.companion.restLabel, systemImage: "moon.stars.fill")
                Spacer()
                Text(String(format: "%d:%02d remaining", model.restSecondsRemaining / 60, model.restSecondsRemaining % 60))
                    .monospacedDigit()
            }.font(.system(size: 11))
            CareProgress(value: 1 - Double(model.restSecondsRemaining) / (model.companion.napMinutes * 60), tint: accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest progress")
                .accessibilityValue("\(Int(100 * max(0, min(1, 1 - Double(model.restSecondsRemaining) / (model.companion.napMinutes * 60))))) percent")
        }
    }

    /// Presents a routine with its prop, expected effects, and any reason it is unavailable.
    private func actionCard(_ action: CareAction) -> some View {
        let reason = model.pet.unavailableReason(for: action, companion: model.companion)
        return Button { onCare(action) } label: {
            HStack(spacing: 8) {
                PropSprite(prop: .object(for: action, companion: model.companion), size: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title(for: model.companion)).font(.system(size: 11, weight: .semibold))
                    Text(reason ?? action.detail(for: model.companion))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .padding(9)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(model.activeCare == action ? 0.65 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isBusy || model.activeCare != nil || reason != nil)
        .help(reason ?? action.detail(for: model.companion))
        .accessibilityLabel(action.title(for: model.companion))
        .accessibilityHint(reason ?? action.detail(for: model.companion))
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT MOMENTS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(1)
            ForEach(model.pet.recentCare.prefix(3)) { event in
                HStack {
                    Image(systemName: event.action.symbol).foregroundStyle(accent).frame(width: 16)
                    Text(event.action.title(for: model.companion))
                    Spacer()
                    Text(event.date, style: .relative).foregroundStyle(.secondary)
                }.font(.system(size: 10))
            }
        }
    }
}

private struct NeedMeter: View {
    let label: String
    let symbol: String
    let value: Double
    let accent: Color
    private var tint: Color { value < 28 ? .orange : accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: symbol).font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(value.rounded()))%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            CareProgress(value: value / 100, tint: tint)
            Text(value < 28 ? "Needs attention" : value < 60 ? "Doing okay" : "Looking good")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) percent, \(value < 28 ? "needs attention" : "satisfied")")
    }
}

private struct CareProgress: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(tint.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint.gradient)
                        .frame(width: geometry.size.width * max(0, min(1, value)))
                }
        }
        .frame(height: 6)
    }
}
