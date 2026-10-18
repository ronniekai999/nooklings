import SwiftUI

@MainActor
struct ContextControls: View {
    @ObservedObject var model: ByteModel
    @State private var showingSummary = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Context ≈ \(model.contextEstimate.formatted()) / \(model.effectiveContextCap.formatted())")
                    .foregroundStyle(model.contextEstimate > model.effectiveContextCap ? .red : .secondary)
                    .help("Conservative token estimate including images, your draft, and instructions. Provider counts may differ.")
                Spacer()
                if !model.turns.isEmpty {
                    Button("Summary…") { showingSummary = true }.buttonStyle(.plain)
                        .disabled(model.isStreaming)
                        .accessibilityLabel("Review a summary and start a shorter chat")
                }
            }
            if let notice = model.sendNotice {
                Text(notice).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11))
        .sheet(isPresented: $showingSummary) { SummaryEditor(model: model) }
    }
}

@MainActor
private struct SummaryEditor: View {
    @ObservedObject var model: ByteModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Carry the essentials into a new chat").font(.headline)
            Text("These local excerpts are a starting point. Edit them into a summary of the goals, decisions, and details you want to keep. The full thread stays in Saved chats; images stay with that archive.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $summary).font(.body).frame(minHeight: 180)
                .accessibilityLabel("Editable conversation summary")
            if let error = model.storageError ?? model.sendNotice { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save full thread & use summary") {
                    if model.startChatWithSummary(summary) { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isStreaming)
            }
        }
        .padding(20).frame(width: 420, height: 420)
        .onAppear { summary = model.summaryDraft }
    }
}

@MainActor
struct LimitSettings: View {
    @ObservedObject var limits: ChatLimits
    let isClaude: Bool
    let spent: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context & spending").font(.headline)
            Picker("Thread context", selection: $limits.contextTokens) {
                ForEach([4000, 8000, 16_000, 32_000, 64_000, 128_000], id: \.self) { n in
                    Text("\(n.formatted()) estimated tokens").tag(n)
                }
            }
            if isClaude {
                Picker("Reply output cap", selection: $limits.outputTokens) {
                    ForEach([256, 512, 1024, 2048, 4096, 8192, 16_384], id: \.self) { n in Text("\(n) tokens").tag(n) }
                }
                Stepper("Searches per reply: \(limits.searchCap)", value: $limits.searches, in: 0...10)
                HStack {
                    Text("Daily API guard ($)")
                    TextField("0", value: $limits.dailyDollars, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                        .accessibilityLabel("Daily API spending guard in US dollars; zero disables it")
                }
                Text(String(format: "≈ $%.4f tracked today (UTC). Zero disables the guard. Estimates include a search reserve; provider billing can differ. This app cannot enforce your provider's account budget.", spent))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("ChatGPT plan requests do not support output or search-call caps. Set plan and credit limits in Manage usage. The local thread context limit still applies.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link("Manage ChatGPT usage", destination: ChatGPTAuth.usageURL)
            }
        }
    }
}

@MainActor
struct ClaudeModelSettings: View {
    @ObservedObject var model: ByteModel
    @AppStorage("byte.effort", store: AppPreferences.shared) private var effort = "high"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Model", selection: Binding(get: { model.model }, set: { model.selectAnthropicModel($0) })) {
                if !model.anthropicModels.contains(where: { $0.id == model.model }) {
                    Text("\(model.model) · not verified").tag(model.model)
                }
                ForEach(model.anthropicModels) { choice in
                    Text(choice.name + (choice.deprecated ? " · deprecated" : "")).tag(choice.id)
                }
            }.disabled(model.isStreaming || model.isLoadingAnthropicModels)
            Button(model.isLoadingAnthropicModels ? "Checking…" : "Check availability") { model.reloadAnthropicModels() }
                .disabled(model.isStreaming || model.isLoadingAnthropicModels || !model.hasKey)
            if let date = model.anthropicModelsCheckedAt {
                Text("Account catalog checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.modelCatalogError { Text(error).font(.caption).foregroundStyle(.orange) }
            let efforts = model.selectedModel.capabilities.efforts
            if model.selectedModel.capabilities.adaptiveThinking, !efforts.isEmpty {
                Picker("Effort", selection: $effort) {
                    if !efforts.contains(effort) { Text("Provider default").tag(effort) }
                    ForEach(efforts, id: \.self) { Text($0.capitalized).tag($0) }
                }.disabled(model.isStreaming)
            }
            Text(model.pricingStatus).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Provider pricing", destination: ModelCatalog.pricingURL).font(.caption)
        }
    }
}
