import Foundation
import SwiftUI

struct ArcadeCredits: Decodable {
    let dailyFree: Int
    let purchaseCredits: Int
    let total: Int
    let resetsAt: String
}
struct ArcadeSummary: Decodable {
    let credits: ArcadeCredits
    let paidEntryEnabled: Bool
}
struct ArcadeStart: Decodable {
    let credits: ArcadeCredits
    let run: ArcadeRun
}
struct ArcadeRun: Decodable, Identifiable {
    let id: String
    let game: String
    let status: String
    let challenge: String
    let remainingSeconds: Double
    let receivedAt = ContinuousClock.now
    var rewardDeadline: ContinuousClock.Instant { receivedAt.advanced(by: .seconds(remainingSeconds)) }
    private enum CodingKeys: String, CodingKey { case id, game, status, challenge, remainingSeconds }
    var board: [Int]? {
        guard let data = challenge.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(PuzzleChallenge.self, from: data))?.board
    }
    private struct PuzzleChallenge: Decodable { let board: [Int] }
}
struct ArcadeLifeCharge: Decodable {
    let credits: ArcadeCredits
    let canContinue: Bool
}
private struct PendingArcadeLife: Codable {
    let runID: String
    let requestKey: String
}

struct ArcadeCompletion: Encodable {
    var level: Int? = nil
    var completed: Bool? = nil
    var moves: [Int]? = nil
    var coins: [Int]? = nil
    var cookies: [Int]? = nil
}
struct ArcadeAward: Decodable {
    let awardedCoins: Int
    let reason: String
    var message: String {
        if awardedCoins > 0 { return "+\(awardedCoins) Rico coin earned!" }
        switch reason {
        case "puzzle_time_expired": return "Puzzle solved. The 60-second reward time has passed."
        case "no_cookie_challenge": return "Level complete. This level has no Rico challenge yet."
        case "too_reward_pending": return "Stage complete. Too’s Rico challenge is coming later."
        default: return "Level complete. Collect every coin and all 3 B cookies to earn Rico."
        }
    }
}

extension AppState {
    @MainActor
    func refreshArcadeCredits() async {
        guard let customerAPIClient, authenticationStatus == .authenticated else { arcadeCredits = nil; return }
        do {
            let summary = try await customerAPIClient.arcadeSummary()
            arcadeCredits = summary.credits
        } catch { arcadeCredits = nil }
    }

    @MainActor
    func startArcadeRun(game: String) async throws -> ArcadeRun {
        guard let customerAPIClient, authenticationStatus == .authenticated else {
            throw NSError(domain: "Arcade", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in to use arcade credits."])
        }
        guard let currentCustomerID else {
            throw NSError(domain: "Arcade", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please refresh your account before starting a game."])
        }
        try await settlePendingArcadeLife()
        let key = String(currentCustomerID) + ":" + game
        let intent = arcadeStartKeys[key] ?? UUID().uuidString
        arcadeStartKeys[key] = intent
        let response = try await customerAPIClient.startArcadeRun(game: game, requestKey: intent)
        arcadeStartKeys[key] = nil
        arcadeCredits = response.credits
        guard response.run.status == "started" else {
            throw NSError(domain: "Arcade", code: 409, userInfo: [NSLocalizedDescriptionKey: "That game has already ended. Please start a new game."])
        }
        return response.run
    }

    @MainActor
    func chargeArcadeLife(runID: String) async throws -> Bool {
        guard let customerAPIClient, authenticationStatus == .authenticated, let currentCustomerID else {
            throw NSError(domain: "Arcade", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in to sync arcade credits."])
        }
        let storageKey = "arcade.pendingLife.\(currentCustomerID)"
        let saved = UserDefaults.standard.data(forKey: storageKey)
        let pending = saved.flatMap { try? JSONDecoder().decode(PendingArcadeLife.self, from: $0) }
            ?? PendingArcadeLife(runID: runID, requestKey: UUID().uuidString)
        // Persist before sending; a lost response or app restart reuses the same charge key.
        UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: storageKey)
        do {
            let response = try await customerAPIClient.chargeArcadeLife(id: pending.runID, requestKey: pending.requestKey)
            arcadeCredits = response.credits
            UserDefaults.standard.removeObject(forKey: storageKey)
            return response.canContinue
        } catch {
            if case CustomerV2APIError.validation(_, let fields) = error,
               fields["credits"] != nil || fields["run"] != nil {
                UserDefaults.standard.removeObject(forKey: storageKey)
                await refreshArcadeCredits()
                return false
            }
            throw error
        }
    }

    @MainActor
    private func settlePendingArcadeLife() async throws {
        guard let currentCustomerID,
              let data = UserDefaults.standard.data(forKey: "arcade.pendingLife.\(currentCustomerID)"),
              let pending = try? JSONDecoder().decode(PendingArcadeLife.self, from: data) else { return }
        _ = try await chargeArcadeLife(runID: pending.runID)
    }

    @MainActor
    func finishArcadeRun(id: String, result: ArcadeCompletion) async throws -> String {
        guard let customerAPIClient, authenticationStatus == .authenticated else {
            throw NSError(domain: "Arcade", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in to sync your reward."])
        }
        let reward = try await customerAPIClient.completeArcadeRun(id: id, result: result)
        await refreshDashboardAndRewards()
        return reward.message
    }
}

struct ArcadeCreditBalanceView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket.fill").font(.system(size: 23)).foregroundStyle(FBColors.cookieOrange)
            Text(appState.arcadeCredits.map { "\($0.total) credits available" } ?? "— credits available")
                .font(.custom("AvenirNext-DemiBold", size: 17))
            Spacer(minLength: 0)
        }.padding(16).background(FBColors.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
