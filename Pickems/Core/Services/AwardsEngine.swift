import Foundation
import SwiftUI

enum WeekAwardsEngine {
    struct Result: Equatable {
        var sharpshooterUserId: String?
        var sharpshooterName: String?
        var heartbreakerUserId: String?
        var heartbreakerName: String?
        var contrarianUserId: String?
        var contrarianName: String?
    }

    static func compute(picks: [UserPick], games: [SlateGame], members: [GroupMember]) -> Result {
        guard !picks.isEmpty, !games.isEmpty else { return Result() }
        let nameById = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })

        var bestWins = -1
        var sharp: String?
        var nearMissBest = -1
        var heart: String?
        var uniqueBest = -1
        var contra: String?

        var pickCounts: [String: [String: Int]] = [:]
        for game in games {
            var counts: [String: Int] = [:]
            for pick in picks {
                if let team = pick.picks[game.id] {
                    counts[team, default: 0] += 1
                }
            }
            pickCounts[game.id] = counts
        }

        for pick in picks {
            let scored = ScoringEngine.scorePicks(
                picks: pick.picks,
                games: games,
                confidenceGameId: pick.confidenceGameId
            )
            let wins = scored.wins
            if wins > bestWins {
                bestWins = wins
                sharp = pick.userId
            }

            var nearMisses = 0
            var uniqueCorrect = 0
            for game in games where game.status == .final {
                guard let picked = pick.picks[game.id],
                      let home = game.homeScore,
                      let away = game.awayScore else { continue }
                guard let covered = game.coveredTeamId(homeScore: home, awayScore: away) else { continue }
                if covered != picked {
                    let margin = abs(
                        Double(home - away) + (game.spreadTeamId == game.homeTeamId ? -abs(game.spread) : abs(game.spread))
                    )
                    if margin <= 3 { nearMisses += 1 }
                } else if pickCounts[game.id]?[picked] == 1 {
                    uniqueCorrect += 1
                }
            }
            if nearMisses > nearMissBest {
                nearMissBest = nearMisses
                heart = pick.userId
            }
            if uniqueCorrect > uniqueBest {
                uniqueBest = uniqueCorrect
                contra = pick.userId
            }
        }

        return Result(
            sharpshooterUserId: sharp,
            sharpshooterName: sharp.flatMap { nameById[$0] },
            heartbreakerUserId: heart,
            heartbreakerName: heart.flatMap { nameById[$0] },
            contrarianUserId: contra,
            contrarianName: contra.flatMap { nameById[$0] }
        )
    }
}

enum StreakEngine {
    static func currentWinStreak(weeklyRecords: [WeeklyRecord]) -> Int {
        var streak = 0
        for record in weeklyRecords.reversed() {
            if record.wins > record.losses { streak += 1 } else { break }
        }
        return streak
    }

    static func badgeLabel(for streak: Int) -> String? {
        switch streak {
        case 3: return "3-week heater"
        case 4: return "On fire"
        case 5...: return "Unstoppable"
        default: return nil
        }
    }

    static func isPerfectSaturday(wins: Int, losses: Int, slateSize: Int) -> Bool {
        losses == 0 && wins > 0 && wins >= max(slateSize - 1, 1)
    }
}
