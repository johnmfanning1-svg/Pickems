import SwiftUI
import WidgetKit

struct HomeWidgetBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if renderingMode == .accented {
                Color.clear
            } else {
                Color(red: 0.08, green: 0.08, blue: 0.10)
            }
        }
    }
}

struct AccessoryBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}

struct DeadlinePhaseView: View {
    let snapshot: StandingsSnapshot
    let deadline: Date
    let kind: WidgetDeadlineKind
    let now: Date

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.modifier(AccessoryBackground())
        case .accessoryRectangular:
            rectangular.modifier(AccessoryBackground())
        case .systemSmall:
            small.modifier(HomeWidgetBackground())
        case .systemLarge, .systemExtraLarge:
            large.modifier(HomeWidgetBackground())
        default:
            medium.modifier(HomeWidgetBackground())
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            groupLine
            timer(size: 30)
            Text("left")
                .font(.caption.weight(.semibold))
            kindPill
            weekLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                groupLine
                Spacer(minLength: 8)
                Text("Week \(snapshot.weekNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            timer(size: 36)
            HStack(spacing: 8) {
                Text("left")
                    .font(.subheadline.weight(.semibold))
                kindPill
                Spacer(minLength: 0)
            }
            weekLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLine
            Text("Week \(snapshot.weekNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            timer(size: 48)
            HStack(spacing: 8) {
                Text("left")
                    .font(.title3.weight(.semibold))
                kindPill
            }
            weekLine
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(deadline, style: .timer)
                .font(.headline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(kind.label)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Text(deadline, style: .timer)
                .font(.caption.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .widgetAccentable()
            Text(kind == .selections ? "Sel" : "Pick")
                .font(.caption2)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var groupLine: some View {
        Text(snapshot.groupName)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var weekLine: some View {
        Text("Week \(snapshot.weekNumber) · \(deadline.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func timer(size: CGFloat) -> some View {
        Text(deadline, style: .timer)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .widgetAccentable()
    }

    private var kindPill: some View {
        Text(kind.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(renderingMode == .accented ? Color.primary : Color.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(
                    renderingMode == .accented
                        ? Color.primary.opacity(0.18)
                        : Color(red: 0.86, green: 0.15, blue: 0.15)
                )
            }
            .widgetAccentable(renderingMode == .accented)
    }

    private var accessibilityText: String {
        let when = deadline.formatted(.dateTime.weekday(.wide).hour().minute())
        return "\(snapshot.groupName). \(kind.label) \(when). Week \(snapshot.weekNumber)."
    }
}

struct ScoreboardPhaseView: View {
    let snapshot: StandingsSnapshot
    let now: Date

    @Environment(\.widgetFamily) private var family

    private var games: [StandingsSnapshot.SnapshotGame] {
        (snapshot.games ?? []).sorted { $0.kickoff < $1.kickoff }
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge, .systemExtraLarge: return 8
        default: return 0
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.modifier(AccessoryBackground())
        case .accessoryRectangular:
            rectangular.modifier(AccessoryBackground())
        case .systemSmall:
            stacked(showRows: true, recordSize: 32).modifier(HomeWidgetBackground())
        case .systemLarge, .systemExtraLarge:
            stacked(showRows: true, recordSize: 34).modifier(HomeWidgetBackground())
        default:
            stacked(showRows: true, recordSize: 28).modifier(HomeWidgetBackground())
        }
    }

    private func stacked(showRows: Bool, recordSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.groupName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                if snapshot.rank > 0 {
                    Text("#\(snapshot.rank)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .widgetAccentable()
                }
            }
            Text("\(snapshot.weeklyWins)-\(snapshot.weeklyLosses)")
                .font(.system(size: recordSize, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            Text("This week · Week \(snapshot.weekNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if showRows {
                ForEach(games.prefix(rowLimit)) { game in
                    SnapshotGameLine(game: game, now: now, compact: family == .systemSmall)
                }
            }
            if family != .systemSmall, let next = WidgetPhase.nextLockDate(snapshot: snapshot, now: now) {
                Text("Next lock: \(next.formatted(.dateTime.hour().minute()))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardLabel)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text("\(snapshot.weeklyWins)-\(snapshot.weeklyLosses) live")
                .font(.headline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .widgetAccentable()
            Text(snapshot.rank > 0 ? "#\(snapshot.rank) · Week \(snapshot.weekNumber)" : "Week \(snapshot.weekNumber)")
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardLabel)
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Text("\(snapshot.weeklyWins)-\(snapshot.weeklyLosses)")
                .font(.caption.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            Text("Live")
                .font(.caption2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardLabel)
    }

    private var scoreboardLabel: String {
        "Week \(snapshot.weekNumber) scoreboard. \(snapshot.weeklyWins) wins, \(snapshot.weeklyLosses) losses, \(snapshot.groupName)."
    }
}

struct SnapshotGameLine: View {
    let game: StandingsSnapshot.SnapshotGame
    let now: Date
    var compact: Bool = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var showScore: Bool {
        game.isFinal || game.kickoff <= now || game.homeScore != nil || game.awayScore != nil
    }

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            side(
                name: game.awayShortName,
                score: game.awayScore,
                picked: game.userPick == game.awayShortName
            )
            Text(showScore ? "–" : "@")
                .foregroundStyle(.secondary)
            side(
                name: game.homeShortName,
                score: game.homeScore,
                picked: game.userPick == game.homeShortName
            )
            Spacer(minLength: 4)
            Text(trailing.label)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(trailing.color)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(compact ? .caption2 : .caption)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel)
    }

    private func side(name: String, score: Int?, picked: Bool) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .fontWeight(picked ? .bold : .regular)
                .foregroundStyle(picked && renderingMode != .accented ? brandRed : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable(picked)
            if showScore, let score {
                Text("\(score)")
                    .monospacedDigit()
                    .fontWeight(isLeading(score, against: opposing(score, name: name)) ? .bold : .regular)
                    .lineLimit(1)
            }
        }
    }

    private func opposing(_ score: Int, name: String) -> Int? {
        if name == game.awayShortName { return game.homeScore }
        return game.awayScore
    }

    private func isLeading(_ score: Int, against other: Int?) -> Bool {
        guard let other else { return false }
        return score > other
    }

    private var trailing: (label: String, color: Color) {
        if game.isFinal {
            switch game.result {
            case .win: return ("W", resultColor(Color(red: 0.20, green: 0.78, blue: 0.35)))
            case .loss: return ("L", resultColor(brandRed))
            case .push: return ("PUSH", resultColor(.secondary))
            case .pending: return ("FINAL", resultColor(.secondary))
            }
        }
        if game.kickoff <= now {
            return ("LIVE", resultColor(Color(red: 0.22, green: 0.48, blue: 0.92)))
        }
        if game.isLocked {
            return ("LOCK", resultColor(.secondary))
        }
        return (game.kickoff.formatted(.dateTime.hour().minute()), .secondary)
    }

    private func resultColor(_ color: Color) -> Color {
        renderingMode == .accented ? .primary : color
    }

    private var brandRed: Color {
        Color(red: 0.86, green: 0.15, blue: 0.15)
    }

    private var rowLabel: String {
        let pick = game.userPick.map { ", picked \($0)" } ?? ""
        if showScore {
            return "\(game.awayShortName) \(game.awayScore ?? 0), \(game.homeShortName) \(game.homeScore ?? 0)\(pick). \(trailing.label)."
        }
        return "\(game.awayShortName) at \(game.homeShortName)\(pick). \(trailing.label)."
    }
}
