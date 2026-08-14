import Foundation
import FirebaseFirestore

/// Pure helpers so a missing or mismatched Firestore `id` cannot drop a game
/// from `compactMap { try? $0.data(as:) }`.
enum SlateGameDecoding {
    /// Prefers the stored `id` field (pick maps use it), then the document id,
    /// then `espnEventId`.
    static func resolvedId(fieldId: String?, documentId: String?, espnEventId: String?) -> String? {
        let candidates = [fieldId, documentId, espnEventId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            return n.stringValue
        case let i as Int:
            return String(i)
        case let i as Int64:
            return String(i)
        default:
            return nil
        }
    }

    static func doubleValue(_ value: Any?) -> Double {
        switch value {
        case let d as Double: return abs(d)
        case let n as NSNumber: return abs(n.doubleValue)
        case let s as String: return abs(Double(s) ?? 0)
        default: return 0
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    /// Games first (real slate docs), then nominations that are not already on the slate.
    static func mergedSlate(games: [SlateGame], nominations: [Nomination]) -> [SlateGame] {
        var seen = Set<String>()
        var result: [SlateGame] = []
        for game in games {
            let key = game.espnEventId.isEmpty ? game.id : game.espnEventId
            if seen.insert(key).inserted {
                result.append(game)
            }
        }
        for nom in nominations {
            if seen.insert(nom.espnEventId).inserted {
                result.append(nom.asSlateGame())
            }
        }
        return result
    }

    static func make(documentId: String, data: [String: Any], kickoff: Date) -> SlateGame? {
        let fieldId = stringValue(data["id"])
        let espn = stringValue(data["espnEventId"])
        guard let id = resolvedId(fieldId: fieldId, documentId: documentId, espnEventId: espn) else {
            return nil
        }
        let espnEventId = espn ?? id
        let homeName = stringValue(data["homeTeamName"]) ?? "Home"
        let awayName = stringValue(data["awayTeamName"]) ?? "Away"
        let statusRaw = stringValue(data["status"]) ?? SlateGame.GameStatus.scheduled.rawValue
        return SlateGame(
            id: id,
            espnEventId: espnEventId,
            homeTeamId: stringValue(data["homeTeamId"]) ?? "home",
            homeTeamName: homeName,
            homeTeamAbbreviation: stringValue(data["homeTeamAbbreviation"])
                ?? String(homeName.prefix(4)).uppercased(),
            homeTeamLogoURL: stringValue(data["homeTeamLogoURL"]),
            awayTeamId: stringValue(data["awayTeamId"]) ?? "away",
            awayTeamName: awayName,
            awayTeamAbbreviation: stringValue(data["awayTeamAbbreviation"])
                ?? String(awayName.prefix(4)).uppercased(),
            awayTeamLogoURL: stringValue(data["awayTeamLogoURL"]),
            spread: doubleValue(data["spread"]),
            spreadTeamId: stringValue(data["spreadTeamId"])
                ?? stringValue(data["homeTeamId"])
                ?? "home",
            kickoff: kickoff,
            status: SlateGame.GameStatus(rawValue: statusRaw) ?? .scheduled,
            homeScore: intValue(data["homeScore"]),
            awayScore: intValue(data["awayScore"]),
            winnerTeamId: stringValue(data["winnerTeamId"])
        )
    }
}

extension SlateGame {
    static func fromDocument(id documentId: String, data: [String: Any]?) -> SlateGame? {
        guard let data else { return nil }
        let kickoff: Date
        if let timestamp = data["kickoff"] as? Timestamp {
            kickoff = timestamp.dateValue()
        } else if let date = data["kickoff"] as? Date {
            kickoff = date
        } else {
            kickoff = Date.distantPast
        }
        return SlateGameDecoding.make(documentId: documentId, data: data, kickoff: kickoff)
    }
}

extension Nomination {
    func asSlateGame() -> SlateGame {
        SlateGame(
            id: espnEventId,
            espnEventId: espnEventId,
            homeTeamId: homeTeamId ?? "home",
            homeTeamName: homeTeamName,
            homeTeamAbbreviation: homeTeamAbbreviation ?? String(homeTeamName.prefix(4)).uppercased(),
            homeTeamLogoURL: homeTeamLogoURL,
            awayTeamId: awayTeamId ?? "away",
            awayTeamName: awayTeamName,
            awayTeamAbbreviation: awayTeamAbbreviation ?? String(awayTeamName.prefix(4)).uppercased(),
            awayTeamLogoURL: awayTeamLogoURL,
            spread: abs(spread),
            spreadTeamId: spreadTeamId,
            kickoff: kickoff,
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
    }
}
