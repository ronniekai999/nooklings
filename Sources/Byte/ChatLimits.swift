import Foundation
import Combine

@MainActor
final class ChatLimits: ObservableObject {
    private let defaults: UserDefaults
    @Published var contextTokens: Int { didSet { defaults.set(contextTokens, forKey: "byte.contextTokens") } }
    @Published var outputTokens: Int { didSet { defaults.set(outputTokens, forKey: "byte.outputTokens") } }
    @Published var searches: Int { didSet { defaults.set(searches, forKey: "byte.searchLimit") } }
    @Published var dailyDollars: Double { didSet { defaults.set(dailyDollars, forKey: "byte.dailyDollars") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        contextTokens = defaults.object(forKey: "byte.contextTokens") as? Int ?? 32_000
        outputTokens = defaults.object(forKey: "byte.outputTokens") as? Int ?? 2048
        searches = defaults.object(forKey: "byte.searchLimit") as? Int ?? 3
        dailyDollars = defaults.object(forKey: "byte.dailyDollars") as? Double ?? 0
    }
    var inputCap: Int { max(4000, min(128_000, contextTokens)) }
    var outputCap: Int { max(256, min(16_384, outputTokens)) }
    var searchCap: Int { max(0, min(10, searches)) }
    var budget: Double { dailyDollars.isFinite ? max(0, dailyDollars) : 0 }
}

enum ChatContext {
    /// Deliberately conservative text estimate: one token per UTF-8 byte, plus
    /// message framing and an image reserve. Provider counts can still differ.
    static func estimate(turns: [ByteModel.Turn], draft: String, pendingImage: Bool, system: String) -> Int {
        turns.filter { $0.role == .user || $0.failure == nil }.reduce(1024 + system.utf8.count + draft.utf8.count + (pendingImage ? 8192 : 0)) {
            $0 + $1.text.utf8.count + 16 + ($1.imageId != nil || $1.imageB64 != nil ? 8192 : 0)
        }
    }

    static func summaryDraft(turns: [ByteModel.Turn]) -> String {
        let valid = turns.filter { !$0.text.isEmpty && ($0.role == .user || $0.failure == nil) }
        var seen = Set<UUID>()
        let excerpts = (Array(valid.prefix(4)) + Array(valid.suffix(8))).filter { seen.insert($0.id).inserted }
        return excerpts.map {
            "\($0.role == .user ? "You" : "Companion"): \(String($0.text.prefix(320)))\($0.text.count > 320 ? "…" : "")"
        }.joined(separator: "\n\n")
    }
}

/// Persist the local daily estimate independently of provider switches and app
/// restarts. This is a send guard, not a provider-enforced billing ceiling.
struct SpendLedger {
    let defaults: UserDefaults
    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    func amount(at date: Date) -> Double {
        defaults.string(forKey: "byte.spend.day") == day(date) ? defaults.double(forKey: "byte.spend.amount") : 0
    }
    func isIncomplete(at date: Date) -> Bool {
        defaults.string(forKey: "byte.spend.day") == day(date) && defaults.bool(forKey: "byte.spend.incomplete")
    }
    func record(_ cost: Double?, at date: Date) {
        let total = amount(at: date), incomplete = isIncomplete(at: date)
        defaults.set(day(date), forKey: "byte.spend.day")
        defaults.set(total + max(0, cost ?? 0), forKey: "byte.spend.amount")
        defaults.set(incomplete || cost == nil, forKey: "byte.spend.incomplete")
    }
}
