import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tier 2 is deliberately fenced off from the deterministic tools. The model
/// may only handle conversational/free-form speech; any request that sounds
/// like a fact is answered by CompanionTools or refused. It is never asked to
/// invent a distance, hazard, weather condition or service interval.
nonisolated enum CompanionLanguageModel {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static func respond(to prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { return nil }
            let session = LanguageModelSession(
                instructions: """
                You are Ace, a dry, economical on-device companion for a motorcycle app.
                Reply in at most one short sentence. Never invent facts, numbers, \
                directions, distances, weather, hazards, speed limits, service data or \
                the rider's location. If the rider asks for a fact, say you do not have it. \
                Never mention being an AI or a model. No enthusiasm, emoji, police, crash, \
                injury or rider-skill jokes.
                """
            )
            do {
                let response = try await session.respond(to: prompt)
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : String(trimmed.prefix(220))
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
