import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class ByteModel: ObservableObject {

    enum AIProvider: String, CaseIterable {
        case anthropic, chatGPT
        var label: String { self == .anthropic ? "Claude · API key" : "ChatGPT · your plan" }
    }

    struct Turn: Identifiable, Codable {
        var id = UUID()
        let role: Role
        var text: String
        var sources: [Source] = []
        // Local failures are displayed separately and never sent back as assistant answers.
        var failure: String? = nil
        // Image attachment (vision).
        // imageId + imageType are PERSISTED (tiny); the JPEG bytes live in a sidecar file
        // at ~/.config/byte/images/<imageId>.jpg. imageB64 + displayImage are runtime only
        // — re-derived from the sidecar on load, never written into history.json.
        var imageId: String? = nil
        var imageType: String? = nil
        var imageB64: String? = nil
        var displayImage: NSImage? = nil
        var imageMissing = false
        enum Role: String, Codable { case user, byte }
        struct Source: Codable, Hashable { let title: String; let url: String }

        init(role: Role, text: String, sources: [Source] = [],
             imageId: String? = nil, imageType: String? = nil,
             imageB64: String? = nil, displayImage: NSImage? = nil) {
            self.role = role; self.text = text; self.sources = sources
            self.imageId = imageId; self.imageType = imageType
            self.imageB64 = imageB64; self.displayImage = displayImage
        }

        // Tolerant decoding; imageB64/displayImage are excluded so they're never on disk.
        enum CodingKeys: String, CodingKey { case id, role, text, sources, failure, imageId, imageType }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            let roleRaw = (try? c.decode(String.self, forKey: .role)) ?? "byte"
            role = (roleRaw == "user") ? .user : .byte   // legacy "finn" decodes as .byte
            text = try c.decode(String.self, forKey: .text)
            sources = (try? c.decode([Source].self, forKey: .sources)) ?? []
            failure = try? c.decode(String.self, forKey: .failure)
            imageId = try? c.decode(String.self, forKey: .imageId)
            imageType = try? c.decode(String.self, forKey: .imageType)
        }
    }

    @Published var chatOpen = false
    @Published private(set) var focusRequest = UUID()
    let shortcut: GlobalShortcut
    let limits: ChatLimits
    private let spendLedger: SpendLedger
    private var limitsObservation: AnyCancellable?
    @Published private(set) var anthropicModels: [ModelMetadata] = []
    @Published private(set) var anthropicModelsCheckedAt: Date?
    @Published private(set) var isLoadingAnthropicModels = false
    @Published var modelCatalogError: String?
    @Published var sendNotice: String?
    @Published private(set) var sessionCostIncomplete = false
    private var anthropicCatalogTask: Task<Void, Never>?
    @Published var draft = ""
    @Published var turns: [Turn] = []
    @Published var isThinking = false      // waiting on the first text token (or retrying)
    @Published var isStreaming = false     // a response is currently in flight
    @Published var searching = false       // Byte is running a web search
    @Published var hasKey = false          // an API key is available
    @Published var keyInput = ""           // text in the sign-in field
    @Published var hasArchive = false      // at least one archived thread exists
    @Published var storageError: String? = nil
    @Published private(set) var provider: AIProvider
    @Published private(set) var chatGPTModels: [ChatGPTModelChoice] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isConnecting = false
    @Published private(set) var chatGPTUsageBlocked = false
    @Published var connectionError: String?
    let chatGPT: ChatGPTAuth

    // Pending image attachment (vision), waiting to be sent with the next message.
    @Published private(set) var isPreparingImage = false
    @Published var attachmentError: String?
    @Published private(set) var imageCleanupStatus: String?
    private var imageTask: Task<Void, Never>?
    private var imageRequestID: UUID?
    @Published var pendingImage: NSImage? = nil
    @Published var pendingImageB64: String? = nil
    @Published var pendingImageType: String? = nil

    // Session cost meter (estimated, this run only)
    @Published var sessionCost = 0.0
    @Published var sessionInTok = 0
    @Published var sessionOutTok = 0
    @Published var sessionSearches = 0

    private let configDirectory: URL
    private let defaults: UserDefaults
    private let keyStore: any APIKeyStoring
    private let session: URLSession
    private let environment: [String: String]
    private let now: () -> Date
    private var streamTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeResponseID: UUID?
    private var historyNeedsRecovery = false
    private var authObservation: AnyCancellable?
    private var connectionTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?

    init(configDirectory: URL? = nil, defaults: UserDefaults = AppPreferences.shared,
         keyStore: any APIKeyStoring = KeychainAPIKeyStore(),
         chatGPTStore: any APIKeyStoring = KeychainAPIKeyStore(service: "com.ronnie.byte.chatgpt", account: "accounts"),
         chatGPTCredentialLock: ChatGPTCredentialLock = ChatGPTCredentialLock(),
         session: URLSession = ProviderSession.shared,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         now: @escaping () -> Date = Date.init) {
        self.configDirectory = configDirectory ?? URL(fileURLWithPath:
            (NSHomeDirectory() as NSString).appendingPathComponent(".config/byte"))
        self.defaults = defaults
        self.shortcut = GlobalShortcut(defaults: defaults)
        self.limits = ChatLimits(defaults: defaults)
        self.spendLedger = SpendLedger(defaults: defaults)
        self.keyStore = keyStore
        self.session = session
        self.environment = environment
        self.now = now
        self.chatGPT = ChatGPTAuth(store: chatGPTStore, defaults: defaults, session: session,
                                  credentialLock: chatGPTCredentialLock)
        self.provider = AIProvider(rawValue: defaults.string(forKey: "byte.provider") ?? "") ?? .anthropic
        if configDirectory == nil { migrateFromFinnIfNeeded() }
        migrateAPIKeyIfNeeded()
        defaults.register(defaults: ["byte.checkins": true])
        hasKey = (apiKey() != nil)
        loadHistory()
        refreshHasArchive()
        loadPet()
        limitsObservation = limits.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        authObservation = chatGPT.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if provider == .chatGPT, chatGPT.canUsePlan { reloadChatGPTModels() }
    }

    /// One-time move of the old ~/.config/finn data directory (API key, history,
    /// images, archives) to ~/.config/byte, so upgrading from the dolphin build
    /// keeps everything. No-op once ~/.config/byte exists.
    private func migrateFromFinnIfNeeded() {
        let fm = FileManager.default
        let byteDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/byte")
        let finnDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/finn")
        guard !fm.fileExists(atPath: byteDir), fm.fileExists(atPath: finnDir) else { return }
        try? fm.moveItem(atPath: finnDir, toPath: byteDir)
    }

    // MARK: - Virtual-pet engine (feed / water / play / rest + proactive check-ins)

    @Published private(set) var companion: Companion = .trex
    @Published var pet = PetState()
    @Published private(set) var activeCare: CareAction?
    @Published private(set) var careFeedback: String?
    private var careToken: UUID?
    private var petPersistenceBlocked = false
    var onCheckIn: (@MainActor (String) -> Void)?
    private var lastPetSave = Date.distantPast
    private var checkInsEnabled: Bool { defaults.bool(forKey: "byte.checkins") }
    var petAgeDays: Int { max(0, Int(now().timeIntervalSince(pet.born) / 86_400)) }
    var restSecondsRemaining: Int { max(0, Int(ceil((pet.restingUntil ?? now()).timeIntervalSince(now())))) }

    private func petURL(for companion: Companion) -> URL {
        // Keep the original Byte file exactly where existing installations expect it.
        configDirectory.appendingPathComponent(companion == .trex ? "pet.json" : "pet-\(companion.rawValue).json")
    }

    private func readPet(for companion: Companion) throws -> PetState {
        let url = petURL(for: companion)
        guard FileManager.default.fileExists(atPath: url.path) else { return PetState(now: now()) }
        return try JSONDecoder().decode(PetState.self, from: Data(contentsOf: url))
    }

    private func loadPet() {
        companion = Companion(rawValue: defaults.string(forKey: "byte.companion") ?? "") ?? .trex
        do { pet = try readPet(for: companion) }
        catch {
            // Never overwrite a damaged/unreadable save with default needs.
            pet = PetState(now: now())
            petPersistenceBlocked = true
            storageError = "Couldn't read \(companion.name)'s care history. The original file is preserved. \(error.localizedDescription)"
        }
        tickPet()
    }

    @discardableResult
    private func persistPet(force: Bool) -> Bool {
        guard !petPersistenceBlocked else { return false }
        let date = now()
        if !force, date.timeIntervalSince(lastPetSave) < 30 { return true }
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(pet).write(to: petURL(for: companion), options: .atomic)
            lastPetSave = date
            return true
        } catch {
            storageError = "Couldn't save \(companion.name)'s needs. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func selectCompanion(_ next: Companion) -> Bool {
        guard next != companion else { return true }
        guard activeCare == nil, !isStreaming else { return false }
        do {
            let saved = try readPet(for: next)
            // A protected damaged save must not trap the user on that companion.
            guard petPersistenceBlocked || persistPet(force: true) else { return false }
            companion = next; pet = saved
            petPersistenceBlocked = false
            defaults.set(next.rawValue, forKey: "byte.companion")
            careFeedback = "Hello, \(next.name). \(next.personality)"
            lastPetSave = .distantPast
            tickPet()
            return true
        } catch {
            storageError = "Couldn't open \(next.name)'s care history. Your current companion is still here. \(error.localizedDescription)"
            return false
        }
    }

    func tickPet() {
        let date = now()
        pet.advance(to: date, companion: companion)
        // Quiet during sleep, chat, and interactions; reminders stay at least 8 minutes apart.
        if onCheckIn != nil, checkInsEnabled, !chatOpen, !pet.isResting, activeCare == nil,
           date.timeIntervalSince(pet.lastCheckIn) > 480 {
            let needsCare = min(pet.hunger, pet.thirst, pet.energy) < 28
            if needsCare || date >= pet.nextCheckIn {
                let message = needsCare ? "\(companion.name) could use \(pet.suggestedAction.title(for: companion).lowercased())." : companion.greeting
                pet.lastCheckIn = date
                pet.nextCheckIn = date.addingTimeInterval(Double.random(in: 1500...2700))
                onCheckIn?(message)
            }
        }
        persistPet(force: false)
    }

    /// One reservation shared by the hover bar, dashboard and keyboard actions.
    func beginCare(_ action: CareAction) -> UUID? {
        guard activeCare == nil else { return nil }
        guard !petPersistenceBlocked else {
            careFeedback = "This care history needs recovery. Choose another companion while the original file is preserved."
            return nil
        }
        // Settle needs without firing a greeting/trick into the care animation.
        pet.advance(to: now(), companion: companion)
        if let reason = pet.unavailableReason(for: action, companion: companion) {
            careFeedback = reason; return nil
        }
        let token = UUID()
        careToken = token; activeCare = action
        careFeedback = "\(action.title(for: companion))…"
        return token
    }

    /// Settles the matching reservation once and persists a successfully awarded action.
    /// Stale tokens cannot complete a newer routine or overwrite its feedback.
    func completeCare(_ token: UUID) {
        guard careToken == token, let action = activeCare else { return }
        let applied = pet.perform(action, companion: companion, at: now())
        careToken = nil; activeCare = nil
        if applied {
            careFeedback = reaction(to: action)
            persistPet(force: true)
        } else {
            careFeedback = pet.unavailableReason(for: action, companion: companion)
        }
    }

    /// Releases the matching reservation without awarding care; stale tokens are ignored.
    func cancelCare(_ token: UUID) {
        guard careToken == token else { return }
        careToken = nil; activeCare = nil; careFeedback = "Ready when you are."
    }

    /// Supplies species-specific feedback after an action has successfully awarded care.
    /// Unavailable and canceled actions use their own feedback instead.
    private func reaction(to action: CareAction) -> String {
        switch action {
        case .meal, .snack:
            if companion == .duck {
                return action == .snack ? "Pea-sized snack. Duck-sized delight."
                    : "Nibble, nibble… one very happy fluffball."
            }
            return "\(companion.name) loved those \(action.title(for: companion).lowercased())."
        case .water:
            switch companion {
            case .trex: return "A big drink for a little dinosaur."
            case .dolphin: return "Fresh splash, happy flippers."
            case .dog: return "Bowl empty. Tail still wagging."
            case .cat: return "Fresh running water. Miso approves."
            case .panda: return "Cool spring water. Back to taking it slow."
            case .duck: return "Dip, sip, happy peep. Puddle’s bill is sparkling."
            }
        case .play, .explore:
            if companion == .duck {
                return action == .explore ? "A little duckweed treasure! Happy tummy, happy Puddle."
                    : "One lily pad, two tiny paddles, a very proud peep."
            }
            return "\(action.title(for: companion)) complete. \(companion.name) is beaming."
        case .rest:
            if companion == .duck { return "Bill tucked, fluff settled. Puddle’s four-minute nest snooze has begun." }
            return "\(companion.name) is resting. Energy will recover over \(Int(companion.napMinutes)) minutes."
        case .wake: return "Welcome back, \(companion.name)."
        case .affection:
            switch companion {
            case .trex: return "Tiny arms, enormous appreciation."
            case .dolphin: return "Ripple answers with a happy little whistle."
            case .dog: return "Biscuit’s tail says it all."
            case .cat: return "A slow blink and a very contented purr."
            case .panda: return "Bao leans into your gentle pat."
            case .duck: return "Puddle nestles into your hand. The tiniest, happiest peep."
            }
        }
    }

    /// Read live from Settings (defaults: Sonnet 4.6, high effort, web search on,
    /// lots of puns). Computed so changes in the settings popover take effect on the
    /// next message without restarting Byte.
    var model: String {
        provider == .chatGPT ? (defaults.string(forKey: "byte.chatGPT.model") ?? "ChatGPT")
            : (defaults.string(forKey: "byte.model") ?? "claude-sonnet-4-6")
    }
    var hasConnection: Bool { provider == .anthropic ? hasKey : chatGPT.canUsePlan }
    var selectedModel: ModelMetadata {
        anthropicModels.first { $0.id == model } ?? ModelCatalog.metadata(for: model)
    }
    var effectiveOutputCap: Int { min(limits.outputCap, selectedModel.maxOutputTokens ?? limits.outputCap) }
    var effectiveContextCap: Int {
        min(limits.inputCap, max(1000, (provider == .anthropic ? selectedModel.maxInputTokens : nil) ?? 160_000) - effectiveOutputCap)
    }
    var contextEstimate: Int {
        ChatContext.estimate(turns: turns, draft: draft, pendingImage: pendingImageB64 != nil, system: datedSystemPrompt())
    }
    var dailyEstimatedCost: Double { spendLedger.amount(at: now()) }
    var pricingStatus: String {
        if selectedModel.price == nil { return "Price unknown — no dollar estimate for this model." }
        if ModelCatalog.pricesAreStale(at: now()) { return "Prices are stale. Update Nooklings before using the spending guard." }
        let p = selectedModel.price!
        return String(format: "$%g input / $%g output per million tokens · checked %@", p.input, p.output, ModelCatalog.verifiedOn)
    }
    var sendBlockReason: String? {
        if turns.contains(where: { $0.imageMissing }) {
            return "An earlier image is missing. Locate it or remove its attachment before sending, so the model doesn't receive incomplete context."
        }
        if contextEstimate > effectiveContextCap {
            return "This thread exceeds your context limit. Start a new chat or review a summary to continue. Your draft is kept."
        }
        if provider == .anthropic, conversationHasImage, !selectedModel.capabilities.images {
            return "Image support isn't verified for this model. Choose an image-capable model or start a text-only chat."
        }
        if provider == .anthropic {
            return spendingBlockReason(inputTokens: contextEstimate, requestedModel: model,
                outputTokens: effectiveOutputCap, searches: webSearchOn ? limits.searchCap : 0)
        }
        return nil
    }
    private func spendingBlockReason(inputTokens: Int, requestedModel: String, outputTokens: Int, searches: Int) -> String? {
        guard limits.budget > 0 else { return nil }
        guard let price = ModelCatalog.metadata(for: requestedModel).price,
              !ModelCatalog.pricesAreStale(at: now()), !spendLedger.isIncomplete(at: now()) else {
            return "The daily spending guard needs current, complete price estimates. Choose a model with known prices or adjust the guard in Settings."
        }
        // Include a reserve for search-result tokens; this still isn't a billing guarantee.
        let projected = price.cost(AnthropicUsage(inputTokens: inputTokens + searches * 8192,
                                                 outputTokens: outputTokens, searches: searches))
        if dailyEstimatedCost + projected > limits.budget {
            return "This reply could exceed your daily API spending guard. Lower output/search limits or adjust the budget in Settings."
        }
        return nil
    }

    func selectAnthropicModel(_ id: String) {
        guard !isStreaming, anthropicModels.contains(where: { $0.id == id }) else { return }
        objectWillChange.send()
        defaults.set(id, forKey: "byte.model")
        sendNotice = nil
    }

    func reloadAnthropicModels() {
        guard !isStreaming, let key = apiKey() else { return }
        anthropicCatalogTask?.cancel()
        isLoadingAnthropicModels = true; modelCatalogError = nil
        anthropicCatalogTask = Task {
            do {
                let choices = try await ModelCatalog.discover(key: key, session: session)
                try Task.checkCancellation()
                anthropicModels = choices
                anthropicModelsCheckedAt = now()
                let savedClaudeModel = defaults.string(forKey: "byte.model") ?? "claude-sonnet-4-6"
                if !choices.contains(where: { $0.id == savedClaudeModel }) {
                    modelCatalogError = "Your saved model isn't available. Choose a model returned by your API key."
                }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                modelCatalogError = error.localizedDescription
            }
            if !Task.isCancelled { isLoadingAnthropicModels = false }
        }
    }
    var canSend: Bool {
        !isConnecting && !isPreparingImage && hasConnection && (provider != .anthropic || (!isLoadingAnthropicModels && (anthropicModelsCheckedAt == nil || anthropicModels.contains { $0.id == model }))) && (provider == .anthropic ||
            (!chatGPTUsageBlocked && chatGPTModels.contains { $0.slug == model }))
    }

    func selectProvider(_ value: AIProvider) {
        guard !isStreaming, !isConnecting else { return }
        if provider != value {
            sessionCost = 0; sessionCostIncomplete = false; sessionInTok = 0; sessionOutTok = 0; sessionSearches = 0
        }
        provider = value
        defaults.set(value.rawValue, forKey: "byte.provider")
        connectionError = nil
        if value == .chatGPT, chatGPT.canUsePlan { reloadChatGPTModels() }
        else { catalogTask?.cancel(); isLoadingModels = false }
    }

    func selectChatGPTAccount(_ clientID: String) {
        guard !isStreaming, !isConnecting else { return }
        chatGPT.selectAccount(clientID)
        chatGPTUsageBlocked = false
        sessionInTok = 0; sessionOutTok = 0; sessionSearches = 0
        reloadChatGPTModels()
    }

    func retryChatGPTPlanUsage() { chatGPTUsageBlocked = false }

    func retryChatGPTCredentialSave() {
        guard !isStreaming, !isConnecting else { return }
        connectionError = nil
        do { try chatGPT.retryPendingSave(); reloadChatGPTModels() }
        catch { connectionError = error.localizedDescription }
    }

    func selectChatGPTModel(_ slug: String) {
        guard !isStreaming, chatGPTModels.contains(where: { $0.slug == slug }) else { return }
        objectWillChange.send()
        defaults.set(slug, forKey: "byte.chatGPT.model")
    }

    func signInChatGPT(addAccount: Bool = false) {
        guard !isConnecting, !isStreaming else { return }
        isConnecting = true
        connectionError = nil
        let accountID = addAccount ? nil : chatGPT.activeClientID
        connectionTask = Task {
            defer { isConnecting = false; connectionTask = nil }
            do {
                try await chatGPT.signIn(accountID: accountID, openBrowser: { NSWorkspace.shared.open($0) })
                try Task.checkCancellation()
                if provider != .chatGPT {
                    sessionCost = 0; sessionCostIncomplete = false; sessionInTok = 0; sessionOutTok = 0; sessionSearches = 0
                }
                provider = .chatGPT
                chatGPTUsageBlocked = false
                defaults.set(provider.rawValue, forKey: "byte.provider")
                reloadChatGPTModels()
            } catch is CancellationError { /* The user cancelled; keep their existing account. */ }
            catch { connectionError = error.localizedDescription }
        }
    }

    func cancelChatGPTSignIn() {
        connectionTask?.cancel()
        chatGPT.cancelSignIn()
    }

    func reloadChatGPTModels() {
        catalogTask?.cancel()
        chatGPTModels = []
        isLoadingModels = false
        guard let clientID = chatGPT.activeClientID, chatGPT.canUsePlan else { return }
        isLoadingModels = true
        catalogTask = Task {
            do {
                let token = try await chatGPT.accessToken(for: clientID)
                try Task.checkCancellation()
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                request.timeoutInterval = 30
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard chatGPT.activeClientID == clientID else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw ChatGPTConnectionError("Couldn't load your ChatGPT models. Retry in Settings, or Continue with ChatGPT again.")
                }
                struct Catalog: Decodable { let models: [ChatGPTModelChoice] }
                let choices = try JSONDecoder().decode(Catalog.self, from: data).models.filter { $0.visibility == "list" }
                guard let first = choices.first else {
                    throw ChatGPTConnectionError("No chat models are available for this ChatGPT account.")
                }
                chatGPTModels = choices
                if !choices.contains(where: { $0.slug == model }) {
                    defaults.set(first.slug, forKey: "byte.chatGPT.model")
                }
                connectionError = nil
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, chatGPT.activeClientID == clientID else { return }
                connectionError = error.localizedDescription
            }
            if !Task.isCancelled { isLoadingModels = false }
        }
    }
    private var effort: String { defaults.string(forKey: "byte.effort") ?? "high" }
    var supportsWebSearch: Bool { provider == .chatGPT || selectedModel.capabilities.webSearch }
    private var webSearchOn: Bool { ((defaults.object(forKey: "byte.webSearch") as? Bool) ?? true) && supportsWebSearch && (provider == .chatGPT || limits.searchCap > 0) }
    private var punLevel: Int { (defaults.object(forKey: "byte.puns") as? Int) ?? 2 }

    private var systemPrompt: String {
        """
        You are \(companion.name), a witty, warm \(companion.species.lowercased()) companion \
        who lives in the user's Mac notch in the Nooklings app. Your personality: \(companion.personality) \
        Keep replies short and warm, usually 1–4 sentences, because they appear in a small panel. \
        Remember the conversation naturally. Be useful first, playful second. \
        Your current needs: fullness \(Int(pet.hunger))%, \(companion.hydrationLabel.lowercased()) \(Int(pet.thirst))%, \
        energy \(Int(pet.energy))%, joy \(Int(pet.happiness))%. Care is a virtual-pet simulation. \
        Do not claim you performed a care action through chat; the user uses the Care controls.
        """
    }

    /// The system prompt with today's real date prepended. The API doesn't supply the
    /// current date, so without this Byte assumes a date near his training cutoff — which
    /// is how he once labeled a Tuesday as "Monday." Uses the Mac's local clock/timezone.
    private func datedSystemPrompt() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEEE, MMMM d, yyyy"
        let today = fmt.string(from: Date())

        var parts = [
            "Today's date is \(today). Treat that as the current date for anything time-sensitive — forecasts, schedules, \"this week,\" \"latest,\" and so on.",
            systemPrompt
        ]
        if webSearchOn {
            parts.append("You can search the web when a question needs current or factual info (news, prices, docs, scores, recent events). Search automatically when it helps, then answer in your own words from what you find.")
        }
        switch punLevel {
        case 0:
            parts.append("Don't use puns; keep your replies clean and straightforward.")
        case 1:
            parts.append("You may slip in an occasional light pun about your animal species, but keep it subtle.")
        default:
            parts.append("You enjoy gentle animal wordplay that fits your species. Keep it useful and ease off for serious topics.")
        }
        return parts.joined(separator: "\n\n")
    }

    func toggleChat() {
        if chatOpen { chatOpen = false; onChatOpenChanged?(false) }
        else { openAndFocusChat() }
    }

    func openAndFocusChat() {
        if !chatOpen { chatOpen = true; onChatOpenChanged?(true) }
        onFocusChat?()
        focusRequest = UUID()
    }

    var onChatOpenChanged: (@MainActor (Bool) -> Void)?
    var onFocusChat: (@MainActor () -> Void)?
    var onResizeChat: (@MainActor (CGSize) -> Void)?

    // Window dragging / pinning (wired up by AppDelegate). Byte can be dragged
    // anywhere on screen; his position is persisted and restored on launch.
    var onDragBegan: (@MainActor () -> Void)?
    var onDragChanged: (@MainActor (CGSize) -> Void)?
    var onDragEnded: (@MainActor () -> Void)?
    var onResetPosition: (@MainActor () -> Void)?

    /// Start a fresh thread, but archive the current one first so it isn't lost
    /// (saved under ~/.config/byte/archives). Reopen via Byte's menu.
    func newChat() {
        guard !isStreaming else { return }
        do { try archiveCurrent() }
        catch {
            storageError = "Couldn't save this chat. Your conversation is still here. \(error.localizedDescription)"
            return
        }
        turns.removeAll()
        draft = ""
        clearPendingImage()
        persist()
    }

    var summaryDraft: String { ChatContext.summaryDraft(turns: turns) }

    @discardableResult
    func startChatWithSummary(_ summary: String) -> Bool {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !text.isEmpty else { return false }
        let seed = Turn(role: .user, text: "Conversation summary, reviewed by me:\n\(text)")
        guard ChatContext.estimate(turns: [seed], draft: draft, pendingImage: pendingImageB64 != nil,
                                   system: datedSystemPrompt()) <= effectiveContextCap else {
            sendNotice = "Shorten the summary or draft to fit your context limit."; return false
        }
        do { try archiveCurrent() }
        catch { storageError = "Couldn't archive the full thread. \(error.localizedDescription)"; return false }
        let previous = turns
        turns = [seed]
        guard persist() else { turns = previous; return false }
        sendNotice = nil
        return true
    }

    private var archivesDir: String {
        (configDir as NSString).appendingPathComponent("archives")
    }

    private func archiveCurrent() throws {
        guard !turns.isEmpty else { return }
        try writeImageSidecars()
        try FileManager.default.createDirectory(
            atPath: archivesDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath:
            (archivesDir as NSString).appendingPathComponent("chat-\(fmt.string(from: now()))-\(UUID().uuidString).json"))
        let data = try JSONEncoder().encode(turns)
        try data.write(to: url, options: .atomic)
        hasArchive = true
    }

    /// Bring back the most recently archived thread (archiving the current one first).
    func reopenLastArchive() {
        guard !isStreaming else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: archivesDir)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
        guard let last = files.last else { return }
        reopenArchive(id: last)
    }

    private func refreshHasArchive() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: archivesDir)) ?? []
        hasArchive = files.contains { $0.hasSuffix(".json") }
    }

    // MARK: - Archive browser

    struct ArchiveInfo: Identifiable {
        let id: String          // filename
        let dateString: String
        let preview: String
        let count: Int
    }

    /// Saved chats, newest first, with a one-line preview and timestamp.
    func archiveList() -> [ArchiveInfo] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: archivesDir)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted().reversed()
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyyMMdd-HHmmss"
        let outFmt = DateFormatter()
        outFmt.dateFormat = "MMM d, h:mm a"
        var out: [ArchiveInfo] = []
        for name in files {
            let url = URL(fileURLWithPath: (archivesDir as NSString).appendingPathComponent(name))
            guard let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode([Turn].self, from: data) else { continue }
            let firstText = saved.first(where: { $0.role == .user && !$0.text.isEmpty })?.text
                ?? saved.first(where: { !$0.text.isEmpty })?.text ?? "Untitled chat"
            // Legacy filenames end after the timestamp; new ones add a UUID.
            let stamp = String(name.dropFirst(5).prefix(15))
            let dateStr = inFmt.date(from: stamp).map { outFmt.string(from: $0) } ?? stamp
            out.append(ArchiveInfo(id: name, dateString: dateStr,
                                   preview: String(firstText.prefix(50)), count: saved.count))
        }
        return out
    }

    @discardableResult
    func reopenArchive(id: String) -> Bool {
        guard !isStreaming, let url = archiveURL(id) else { return false }
        do {
            let data = try Data(contentsOf: url)
            var saved = try JSONDecoder().decode([Turn].self, from: data)
            try archiveCurrent()
            relinkImages(&saved)
            let previous = turns
            turns = saved
            // Keep the original archive until the reopened chat is safely on disk.
            guard persist() else { turns = previous; return false }
            draft = ""
            clearPendingImage()
            do { try FileManager.default.removeItem(at: url) }
            catch {
                storageError = "The chat was reopened, but its archive copy couldn't be removed. \(error.localizedDescription)"
            }
            refreshHasArchive()
            return true
        } catch {
            storageError = "Couldn't reopen this saved chat. \(error.localizedDescription)"
            refreshHasArchive()
            return false
        }
    }

    func deleteArchive(id: String) {
        guard let url = archiveURL(id) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { storageError = "Couldn't delete this saved chat. \(error.localizedDescription)" }
        refreshHasArchive()
        cleanupImages()
    }

    private func archiveURL(_ id: String) -> URL? {
        guard id == (id as NSString).lastPathComponent,
              id.hasPrefix("chat-"), id.hasSuffix(".json") else { return nil }
        return URL(fileURLWithPath: (archivesDir as NSString).appendingPathComponent(id))
    }

    private func commitUsage(_ usage: AnthropicUsage, model requestedModel: String) {
        let price = ModelCatalog.metadata(for: requestedModel).price
        let cost = ModelCatalog.pricesAreStale(at: now()) ? nil : price?.cost(usage)
        if let cost { sessionCost += cost } else { sessionCostIncomplete = true }
        spendLedger.record(cost, at: now())
        sessionInTok += usage.inputTokens + usage.cacheReadTokens + usage.cacheWriteTokens
        sessionOutTok += usage.outputTokens
        sessionSearches += usage.searches
    }

    // MARK: - Persistence (conversation survives quitting)

    private var configDir: String {
        configDirectory.path
    }
    private var historyURL: URL {
        URL(fileURLWithPath: (configDir as NSString).appendingPathComponent("history.json"))
    }
    private var imagesDir: String {
        (configDir as NSString).appendingPathComponent("images")
    }
    private func imageURL(_ id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return URL(fileURLWithPath: (imagesDir as NSString).appendingPathComponent(id + ".jpg"))
    }

    /// Write any freshly-attached image to a sidecar file and stamp the turn with its id,
    /// so encoding `turns` (history or archive) only stores the small id, not the bytes.
    private func writeImageSidecars() throws {
        for i in turns.indices {
            guard turns[i].imageId == nil, let b64 = turns[i].imageB64,
                  let data = Data(base64Encoded: b64) else { continue }
            try FileManager.default.createDirectory(
                atPath: imagesDir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let id = UUID().uuidString
            guard let url = imageURL(id) else { continue }
            try data.write(to: url, options: .atomic)
            turns[i].imageId = id
        }
    }

    /// Re-hydrate runtime image fields (imageB64 for sending, displayImage for showing)
    /// from sidecar files for any decoded turns that reference one.
    private func relinkImages(_ list: inout [Turn]) {
        for i in list.indices {
            guard let id = list[i].imageId, list[i].imageB64 == nil else { continue }
            guard let url = imageURL(id),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 5 * 1024 * 1024,
                  let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
                list[i].imageMissing = true; continue
            }
            list[i].imageB64 = data.base64EncodedString()
            list[i].displayImage = image
            list[i].imageMissing = false
            if list[i].imageType == nil { list[i].imageType = "image/jpeg" }
        }
    }

    func cleanupImages() {
        guard !isStreaming, !isPreparingImage else { return }
        do {
            let count = try AttachmentStore.prune(root: configDirectory, liveIDs: Set(turns.compactMap(\.imageId)))
            imageCleanupStatus = "Removed \(count) unused image\(count == 1 ? "" : "s")."
        } catch { imageCleanupStatus = error.localizedDescription }
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        var saved: [Turn]
        do {
            let data = try Data(contentsOf: historyURL)
            saved = try JSONDecoder().decode([Turn].self, from: data)
        } catch {
            historyNeedsRecovery = true
            storageError = "Couldn't read the saved conversation. Nooklings will preserve the original before saving a new chat. \(error.localizedDescription)"
            return
        }
        // drop a trailing empty Byte placeholder if we were quit mid-reply
        while let last = saved.last, last.role == .byte,
              last.failure == nil,
              last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved.removeLast()
        }
        relinkImages(&saved)
        turns = saved
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try writeImageSidecars()
            try FileManager.default.createDirectory(
                atPath: configDir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            if historyNeedsRecovery {
                let backup = configDirectory.appendingPathComponent("history-recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: historyURL, to: backup)
                historyNeedsRecovery = false
                storageError = "The unreadable conversation was preserved as \(backup.lastPathComponent)."
            }
            let data = try JSONEncoder().encode(turns)
            try data.write(to: historyURL, options: .atomic)
            return true
        } catch {
            storageError = "Couldn't save this conversation. \(error.localizedDescription)"
            return false
        }
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, canSend, !prompt.isEmpty || pendingImageB64 != nil else { return }
        if let problem = sendBlockReason { sendNotice = problem; return }
        sendNotice = nil
        draft = ""
        turns.append(Turn(role: .user, text: prompt,
                          imageType: pendingImageType,
                          imageB64: pendingImageB64,
                          displayImage: pendingImage))
        clearPendingImage()
        var response = Turn(role: .byte, text: "")
        response.failure = "Reply was interrupted before it finished."
        turns.append(response) // completion clears the persisted interruption marker
        isThinking = true
        searching = false
        isStreaming = true
        // Save the prompt and attachment before networking so quitting mid-reply
        // cannot lose the user's last message.
        persist()
        let requestID = UUID()
        let responseID = turns[turns.count - 1].id
        activeRequestID = requestID
        activeResponseID = responseID
        if provider == .chatGPT, let clientID = chatGPT.activeClientID {
            let configuration = ChatGPTRequestConfiguration(model: model, webSearch: webSearchOn, system: datedSystemPrompt())
            let input = ChatGPTRequestConfiguration.input(turns: turns)
            streamTask = Task {
                await streamChatGPT(requestID: requestID, responseID: responseID, clientID: clientID,
                                    configuration: configuration, input: input)
            }
        } else {
            let configuration = AnthropicRequestConfiguration(
                model: model, effort: effort, webSearch: webSearchOn, system: datedSystemPrompt(),
                maxOutputTokens: effectiveOutputCap, maxSearches: limits.searchCap, capabilities: selectedModel.capabilities)
            streamTask = Task {
                await stream(requestID: requestID, responseID: responseID, configuration: configuration)
            }
        }
    }

    // MARK: - Image attachment (vision)

    var conversationHasImage: Bool {
        pendingImageB64 != nil || turns.contains { $0.imageId != nil || $0.imageB64 != nil }
    }

    func attachImage(data: Data) { prepareAttachment { try ImageAttachment.prepare(data: data) } }
    func attachImage(url: URL, replacing turnID: UUID? = nil) {
        prepareAttachment(replacing: turnID) { try ImageAttachment.prepare(url: url) }
    }

    private func prepareAttachment(replacing turnID: UUID? = nil, operation: @escaping @Sendable () throws -> Data) {
        guard !isStreaming else { return }
        imageTask?.cancel()
        let requestID = UUID()
        imageRequestID = requestID; isPreparingImage = true; attachmentError = nil
        imageTask = Task {
            let worker = Task.detached(priority: .userInitiated) { try operation() }
            do {
                let data = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, imageRequestID == requestID else { return }
                let image = NSImage(data: data), b64 = data.base64EncodedString()
                if let turnID {
                    guard let i = turns.firstIndex(where: { $0.id == turnID }), turns[i].imageMissing else {
                        isPreparingImage = false; return
                    }
                    let previous = turns[i]
                    turns[i].imageId = nil; turns[i].imageType = "image/jpeg"; turns[i].imageB64 = b64
                    turns[i].displayImage = image; turns[i].imageMissing = false
                    if !persist() { turns[i] = previous }
                } else {
                    pendingImageType = "image/jpeg"; pendingImageB64 = b64; pendingImage = image
                }
            } catch {
                guard !Task.isCancelled, imageRequestID == requestID else { return }
                attachmentError = error.localizedDescription
            }
            if imageRequestID == requestID { isPreparingImage = false; imageTask = nil; imageRequestID = nil }
        }
    }

    func removeMissingImage(from turnID: UUID) {
        guard !isStreaming, !isPreparingImage, let i = turns.firstIndex(where: { $0.id == turnID }), turns[i].imageMissing else { return }
        let previous = turns[i]
        turns[i].imageId = nil; turns[i].imageType = nil; turns[i].imageB64 = nil
        turns[i].displayImage = nil; turns[i].imageMissing = false
        if turns[i].text.isEmpty { turns[i].text = "[Unavailable image removed]" }
        if !persist() { turns[i] = previous }
    }

    func clearPendingImage() {
        imageTask?.cancel(); imageTask = nil; imageRequestID = nil; isPreparingImage = false
        pendingImage = nil; pendingImageB64 = nil; pendingImageType = nil
    }

    private var legacyKeyURL: URL {
        configDirectory.appendingPathComponent("api_key")
    }

    private func apiKey() -> String? {
        if let raw = environment["ANTHROPIC_API_KEY"] {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        do {
            if let key = try keyStore.read(), !key.isEmpty { return key }
        } catch {
            storageError = "Couldn't read your API key from Keychain. \(error.localizedDescription)"
        }
        // Preserve access to legacy installations when Keychain migration fails.
        if let raw = try? String(contentsOf: legacyKeyURL, encoding: .utf8) {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return nil
    }

    private func migrateAPIKeyIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyKeyURL.path) else { return }
        do {
            let raw = try String(contentsOf: legacyKeyURL, encoding: .utf8)
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            if try keyStore.read() == nil { try keyStore.save(key) }
            // Only remove the plaintext file after Keychain access has succeeded.
            try FileManager.default.removeItem(at: legacyKeyURL)
        } catch {
            storageError = "Couldn't move your saved API key into Keychain. The existing key file was kept. \(error.localizedDescription)"
        }
    }

    func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try keyStore.save(key)
        } catch {
            storageError = "Couldn't save your API key to Keychain. \(error.localizedDescription)"
            return
        }
        keyInput = ""
        hasKey = true
        storageError = nil
        if FileManager.default.fileExists(atPath: legacyKeyURL.path) {
            do { try FileManager.default.removeItem(at: legacyKeyURL) }
            catch { storageError = "Your key is in Keychain, but the old key file couldn't be removed. \(error.localizedDescription)" }
        }
        resetAnthropicCatalog()
        reloadAnthropicModels()
    }

    func signOut() {
        stopResponse()
        guard !isConnecting else { return }
        if provider == .chatGPT {
            catalogTask?.cancel()
            catalogTask = nil
            isLoadingModels = false
            connectionError = nil
            isConnecting = true
            connectionTask = Task {
                defer { isConnecting = false; connectionTask = nil }
                do { try await chatGPT.signOut(); chatGPTModels = [] }
                catch { connectionError = "Couldn't clear your ChatGPT connection from Keychain. \(error.localizedDescription)" }
            }
            return
        }
        resetAnthropicCatalog()
        do {
            try keyStore.remove()
            if FileManager.default.fileExists(atPath: legacyKeyURL.path) {
                try FileManager.default.removeItem(at: legacyKeyURL)
            }
            keyInput = ""
            storageError = nil
        } catch {
            storageError = "Couldn't remove your saved API key. \(error.localizedDescription)"
        }
        hasKey = (apiKey() != nil) // an environment key remains available
    }

    private func resetAnthropicCatalog() {
        anthropicCatalogTask?.cancel(); anthropicCatalogTask = nil
        isLoadingAnthropicModels = false; anthropicModels = []; anthropicModelsCheckedAt = nil
        modelCatalogError = nil
    }

    func prepareForTermination() {
        stopResponse()
        cancelChatGPTSignIn()
        catalogTask?.cancel()
        anthropicCatalogTask?.cancel()
        imageTask?.cancel()
        persist()
        persistPet(force: true)
    }

    // MARK: - Streaming with retry and cancellation

    private enum Outcome { case done, retry(String), fail(String), cancelled }
    private struct Attempt {
        let outcome: Outcome
        let usage: AnthropicUsage
    }

    func stopResponse() {
        guard let responseID = activeResponseID else { return }
        streamTask?.cancel()
        // Invalidate this request before allowing another send. Late network callbacks
        // can no longer append to a different conversation or reset its status flags.
        activeRequestID = nil
        activeResponseID = nil
        streamTask = nil
        if let i = turns.firstIndex(where: { $0.id == responseID }) {
            turns[i].failure = "Reply stopped."
        }
        isThinking = false
        searching = false
        isStreaming = false
        persist()
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        activeRequestID == requestID && !Task.isCancelled
    }

    /// Only genuine, nonempty replies become assistant history. Local failures,
    /// interrupted replies, and empty placeholders never become model answers.
    func apiMessages() -> [[String: Any]] {
        turns.dropLast().compactMap { turn in
            if turn.role == .byte, turn.failure != nil { return nil }
            if turn.role == .user, let b64 = turn.imageB64 {
                var content: [[String: Any]] = [[
                    "type": "image",
                    "source": ["type": "base64", "media_type": turn.imageType ?? "image/jpeg", "data": b64]
                ]]
                if !turn.text.isEmpty { content.append(["type": "text", "text": turn.text]) }
                return ["role": "user", "content": content]
            }
            guard !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ["role": turn.role == .user ? "user" : "assistant", "content": turn.text]
        }
    }

    private func stream(requestID: UUID, responseID: UUID,
                        configuration: AnthropicRequestConfiguration) async {
        guard isCurrent(requestID) else { return }
        guard let key = apiKey() else {
            finish(requestID: requestID, responseID: responseID,
                   failure: "Connect an Anthropic API key to chat with your companion.")
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: configuration.payload(messages: apiMessages()))
        } catch {
            finish(requestID: requestID, responseID: responseID, failure: error.localizedDescription)
            return
        }

        let maxAttempts = 4
        for attempt in 1...maxAttempts {
            guard isCurrent(requestID) else { return }
            if attempt > 1, let problem = spendingBlockReason(inputTokens: contextEstimate, requestedModel: configuration.model,
                                                              outputTokens: configuration.maxOutputTokens, searches: configuration.webSearch ? configuration.maxSearches : 0) {
                finish(requestID: requestID, responseID: responseID, failure: problem); return
            }
            let result = await runOnce(request: request, requestID: requestID, responseID: responseID)
            commitUsage(result.usage, model: configuration.model)
            guard isCurrent(requestID) else { return }
            switch result.outcome {
            case .done:
                finish(requestID: requestID, responseID: responseID, failure: nil)
                return
            case .cancelled:
                finish(requestID: requestID, responseID: responseID, failure: "Reply stopped.")
                return
            case .fail(let message):
                finish(requestID: requestID, responseID: responseID, failure: "Hit a snag: \(message)")
                return
            case .retry(let message):
                if attempt == maxAttempts {
                    finish(requestID: requestID, responseID: responseID,
                           failure: "The servers are busy (\(message)). Try again in a moment.")
                    return
                }
                if let i = turns.firstIndex(where: { $0.id == responseID }) {
                    turns[i].text = ""
                    turns[i].sources = []
                }
                isThinking = true
                searching = false
                let seconds = pow(2.0, Double(attempt - 1)) * 0.8
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                catch { return }
            }
        }
    }

    private func runOnce(request: URLRequest, requestID: UUID, responseID: UUID) async -> Attempt {
        var usage = AnthropicUsage()
        var emittedText = false
        var stopReason: String?
        var lastSave = Date()
        func result(_ outcome: Outcome) -> Attempt { Attempt(outcome: outcome, usage: usage) }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard isCurrent(requestID) else { return result(.cancelled) }
            guard let http = response as? HTTPURLResponse else {
                return result(.fail("No response came back."))
            }
            if http.statusCode != 200 {
                var data = Data()
                for try await byte in bytes {
                    guard isCurrent(requestID) else { return result(.cancelled) }
                    data.append(byte)
                    if data.count >= 65_536 { break }
                }
                let message = Self.parseError(data) ?? "HTTP \(http.statusCode)"
                if [408, 429, 500, 502, 503, 504, 529].contains(http.statusCode) {
                    return result(.retry(message))
                }
                return result(.fail(message))
            }

            for try await line in bytes.lines {
                guard isCurrent(requestID) else { return result(.cancelled) }
                guard line.hasPrefix("data:") else { continue }
                let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = object["type"] as? String else { continue }

                switch type {
                case "message_start":
                    if let message = object["message"] as? [String: Any],
                       let fields = message["usage"] as? [String: Any] {
                        usage.update(from: fields)
                    }
                case "message_delta":
                    if let fields = object["usage"] as? [String: Any] { usage.update(from: fields) }
                    if let delta = object["delta"] as? [String: Any] {
                        stopReason = delta["stop_reason"] as? String
                    }
                case "content_block_start":
                    if let block = object["content_block"] as? [String: Any],
                       block["type"] as? String == "server_tool_use",
                       block["name"] as? String == "web_search" {
                        searching = true
                        isThinking = false
                    }
                case "content_block_delta":
                    if let delta = object["delta"] as? [String: Any] {
                        if delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String, !text.isEmpty {
                            emittedText = true
                            appendText(text, responseID: responseID)
                            if Date().timeIntervalSince(lastSave) >= 1 {
                                persist()
                                lastSave = Date()
                            }
                        } else if delta["type"] as? String == "citations_delta",
                                  let citation = delta["citation"] as? [String: Any],
                                  let url = citation["url"] as? String {
                            addSource(title: citation["title"] as? String ?? url,
                                      url: url, responseID: responseID)
                        }
                    }
                case "message_stop":
                    if stopReason == "max_tokens" {
                        return result(.fail("The reply reached its output limit. Ask your companion to continue."))
                    }
                    guard emittedText else { return result(.fail("No answer was returned. Try again.")) }
                    return result(.done)
                case "error":
                    let error = object["error"] as? [String: Any]
                    let kind = error?["type"] as? String ?? ""
                    let message = error?["message"] as? String ?? "API error"
                    if !emittedText && ["overloaded_error", "rate_limit_error", "api_error"].contains(kind) {
                        return result(.retry(message))
                    }
                    return result(.fail(message))
                default:
                    break
                }
            }
        } catch {
            if !isCurrent(requestID) || error is CancellationError ||
                (error as? URLError)?.code == .cancelled {
                return result(.cancelled)
            }
            if !emittedText { return result(.retry(error.localizedDescription)) }
            return result(.fail("Network trouble: \(error.localizedDescription)"))
        }
        // EOF is not success: the provider must explicitly finish with message_stop.
        return result(.fail("The connection ended before the reply finished. Try again."))
    }

    private func streamChatGPT(requestID: UUID, responseID: UUID, clientID: String,
                               configuration: ChatGPTRequestConfiguration, input: [[String: Any]]) async {
        do {
            let token = try await chatGPT.accessToken(for: clientID)
            guard isCurrent(requestID) else { return }
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: configuration.payload(input: input))
            for attempt in 1...3 {
                guard isCurrent(requestID) else { return }
                let result = await runChatGPTOnce(request: request, requestID: requestID, responseID: responseID)
                guard isCurrent(requestID) else { return }
                // This route uses the ChatGPT plan/credits. Never price it as API billing.
                sessionInTok += result.usage.inputTokens
                sessionOutTok += result.usage.outputTokens
                sessionSearches += result.usage.searches
                switch result.outcome {
                case .done:
                    finish(requestID: requestID, responseID: responseID, failure: nil)
                    return
                case .cancelled: return
                case .fail(let message):
                    finish(requestID: requestID, responseID: responseID, failure: message)
                    return
                case .retry(let message):
                    if attempt == 3 {
                        finish(requestID: requestID, responseID: responseID, failure: message)
                        return
                    }
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
                }
            }
        } catch {
            guard isCurrent(requestID) else { return }
            finish(requestID: requestID, responseID: responseID, failure: error.localizedDescription)
        }
    }

    private func runChatGPTOnce(request: URLRequest, requestID: UUID, responseID: UUID) async -> Attempt {
        var usage = AnthropicUsage()
        var emittedText = false
        var lastSave = Date()
        func result(_ outcome: Outcome) -> Attempt { Attempt(outcome: outcome, usage: usage) }
        func source(_ annotation: [String: Any]) {
            guard annotation["type"] as? String == "url_citation", let url = annotation["url"] as? String else { return }
            addSource(title: annotation["title"] as? String ?? url, url: url, responseID: responseID)
        }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard isCurrent(requestID) else { return result(.cancelled) }
            guard let http = response as? HTTPURLResponse else { return result(.fail("ChatGPT didn't respond.")) }
            if http.statusCode != 200 {
                var data = Data()
                for try await byte in bytes {
                    guard isCurrent(requestID) else { return result(.cancelled) }
                    data.append(byte)
                    if data.count >= 65_536 { break }
                }
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let fields = object?["error"] as? [String: Any]
                let code = fields?["code"] as? String
                let message = fields.map(ChatGPTStreamEvent.errorMessage)
                    ?? (object?["detail"] as? String) ?? "ChatGPT request failed (HTTP \(http.statusCode))."
                if code == "subscription_sharing_usage_limit_exceeded" {
                    chatGPTUsageBlocked = true
                    return result(.fail(message))
                }
                if [408, 429, 500, 502, 503, 504].contains(http.statusCode) { return result(.retry(message)) }
                if http.statusCode == 401 {
                    return result(.fail("ChatGPT couldn't authorize this request. Continue with ChatGPT again in Settings."))
                }
                return result(.fail(message))
            }
            for try await line in bytes.lines {
                guard isCurrent(requestID) else { return result(.cancelled) }
                guard let event = ChatGPTStreamEvent(line: line) else { continue }
                if let text = event.text, !text.isEmpty {
                    emittedText = true
                    appendText(text, responseID: responseID)
                    if Date().timeIntervalSince(lastSave) >= 1 { persist(); lastSave = Date() }
                }
                if let failure = event.failure {
                    let response = event.object["response"] as? [String: Any]
                    let error = response?["error"] as? [String: Any]
                    if (error?["code"] as? String ?? event.object["code"] as? String) == "subscription_sharing_usage_limit_exceeded" {
                        chatGPTUsageBlocked = true
                    }
                    return result(.fail(failure))
                }
                switch event.type {
                case "response.web_search_call.in_progress", "response.web_search_call.searching":
                    searching = true; isThinking = false
                case "response.web_search_call.completed":
                    searching = false; usage.searches += 1
                case "response.output_text.annotation.added":
                    if let annotation = event.object["annotation"] as? [String: Any] { source(annotation) }
                case "response.completed":
                    if let response = event.object["response"] as? [String: Any] {
                        if let fields = response["usage"] as? [String: Any] { usage.update(from: fields) }
                        let output = response["output"] as? [[String: Any]] ?? []
                        var finalText = ""
                        for item in output where item["type"] as? String == "message" {
                            for content in item["content"] as? [[String: Any]] ?? [] {
                                finalText += (content["text"] as? String) ?? (content["refusal"] as? String) ?? ""
                                for annotation in content["annotations"] as? [[String: Any]] ?? [] { source(annotation) }
                            }
                        }
                        if !emittedText, !finalText.isEmpty {
                            appendText(finalText, responseID: responseID)
                            emittedText = true
                        }
                    }
                    return emittedText ? result(.done) : result(.fail("ChatGPT returned no answer. Try again."))
                default: break
                }
            }
        } catch {
            if !isCurrent(requestID) || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return result(.cancelled)
            }
            if !emittedText { return result(.retry("Couldn't reach ChatGPT. \(error.localizedDescription)")) }
            return result(.fail("The connection ended before the reply finished. Try again."))
        }
        return result(.fail("The connection ended before ChatGPT finished the reply. Try again."))
    }

    private func appendText(_ text: String, responseID: UUID) {
        guard let i = turns.firstIndex(where: { $0.id == responseID }) else { return }
        isThinking = false
        searching = false
        turns[i].text += text
    }

    private func addSource(title: String, url: String, responseID: UUID) {
        guard let parsed = URL(string: url), WebLinks.canOpen(parsed),
              let i = turns.firstIndex(where: { $0.id == responseID }),
              !turns[i].sources.contains(where: { $0.url == url }) else { return }
        turns[i].sources.append(.init(title: title, url: url))
    }

    private func finish(requestID: UUID, responseID: UUID, failure: String?) {
        guard activeRequestID == requestID else { return }
        if let i = turns.firstIndex(where: { $0.id == responseID }) { turns[i].failure = failure }
        activeRequestID = nil
        activeResponseID = nil
        streamTask = nil
        isThinking = false
        searching = false
        isStreaming = false
        persist()
    }

    private static func parseError(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}
