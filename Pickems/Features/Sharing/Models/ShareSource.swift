import Foundation

enum ShareSource {
    case weekly(WeeklyResult)
    case season(SeasonStanding)

    func makeShareableResult(tone: ShareTone = .auto) -> ShareableResult {
        switch self {
        case .weekly(let result):
            return ShareableResult(weekly: result, tone: tone)
        case .season(let standing):
            return ShareableResult(season: standing, tone: tone)
        }
    }

    var ctaTitle: String {
        switch self {
        case .weekly(let result):
            return "Share \(result.recordText)"
        case .season(let standing):
            return "Share #\(standing.rank)"
        }
    }
}
