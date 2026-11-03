import SwiftUI
import WidgetKit

struct DeadlinePhaseView: View {
    let snapshot: StandingsSnapshot
    let deadline: Date
    let kind: WidgetDeadlineKind
    let now: Date
    var linkRows: Bool = false

    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var systemShowsBackground
    @Environment(\.showsWidgetBackgroundOverride) private var showsBackgroundOverride
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var family: WidgetFamily { familyOverride ?? systemFamily }
    private var showsBackground: Bool { showsBackgroundOverride ?? systemShowsBackground }

    private var enlarged: Bool { !showsBackground }
    private var stale: Bool { WidgetPhase.isStale(snapshot: snapshot, now: now) }
    private var owed: (made: Int, total: Int, left: Int)? {
        WidgetPicksOwed.owed(made: snapshot.picksMade, total: snapshot.picksTotal)
    }
    private var allIn: Bool { owed?.left == 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.modifier(AccessoryBackground())
        case .accessoryRectangular:
            rectangular.modifier(AccessoryBackground())
        case .accessoryInline:
            EmptyView()
        case .systemSmall:
            small.modifier(HomeWidgetBackground(family: family))
        case .systemLarge, .systemExtraLarge:
            large.modifier(HomeWidgetBackground(family: family))
        default:
            medium.modifier(HomeWidgetBackground(family: family))
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            header
            countdownStack
            if stale { WidgetRefreshButton() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            header
            countdownStack
            if stale { WidgetRefreshButton() }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            header
            countdownStack
            if !luminanceReduced, let owed, owed.left > 0 {
                dueList
            }
            if stale { WidgetRefreshButton() }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetEyebrow(text: snapshot.groupName)
            if allIn {
                Text("All picks in ✓")
                    .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                    .foregroundStyle(WidgetStyle.accented(WidgetStyle.winGreen, mode: renderingMode))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                timer(isHero: false)
            } else {
                timer(isHero: true)
                if let owed {
                    Text("\(owed.left) of \(owed.total) left")
                        .font(WidgetStyle.rowFont)
                        .lineLimit(1)
                } else {
                    Text("left")
                        .font(WidgetStyle.rowFont)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var circular: some View {
        Group {
            if let owed {
                Gauge(value: Double(owed.made), in: 0...Double(max(owed.total, 1))) {
                    Text(kind == .selections ? "Sel" : "Picks")
                } currentValueLabel: {
                    Text(owed.left == 0 ? "✓" : "\(owed.left)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                VStack(spacing: 0) {
                    timer(isHero: true)
                    Text(kind == .selections ? "Sel" : "Pick")
                        .font(WidgetStyle.eyebrowFont)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetEyebrow(text: "\(snapshot.groupName) · Wk \(snapshot.weekNumber)")
            if stale {
                WidgetUpdatedLine(date: snapshot.updatedAt)
            }
        }
    }

    @ViewBuilder
    private var countdownStack: some View {
        if allIn {
            Text("All picks in ✓")
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .foregroundStyle(WidgetStyle.accented(WidgetStyle.winGreen, mode: renderingMode))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            timer(isHero: false)
        } else {
            Text(kind == .selections ? "Selections lock in" : "Picks lock in")
                .font(WidgetStyle.titleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            timer(isHero: true)
            if let owed {
                Text("\(owed.left) of \(owed.total) left")
                    .font(WidgetStyle.rowFont)
                    .lineLimit(1)
                if !luminanceReduced {
                    progress(made: owed.made, total: owed.total)
                }
            } else {
                Text("left")
                    .font(WidgetStyle.rowFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dueList: some View {
        let due = (snapshot.games ?? []).filter { $0.userPick == nil && !$0.isFinal }.prefix(4)
        return VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            WidgetEyebrow(text: "Picks due")
            if due.isEmpty {
                Text("Every open game has a pick")
                    .font(WidgetStyle.rowFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(due)) { game in
                    HStack {
                        Text("\(game.awayShortName) @ \(game.homeShortName)")
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(WidgetStyle.rowFont)
                    .widgetLink(linkRows ? WidgetDeepLink.gameURL(snapshot: snapshot, gameId: game.id) : nil)
                }
            }
        }
    }

    private func timer(isHero: Bool) -> some View {
        Text(deadline, style: .timer)
            .font(isHero ? WidgetStyle.heroFont(for: family, enlarged: enlarged) : WidgetStyle.rowFont)
            .monospacedDigit()
            .foregroundStyle(isHero ? Color.primary : Color.secondary)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .widgetAccentable()
    }

    private func progress(made: Int, total: Int) -> some View {
        let fraction = total == 0 ? 0 : CGFloat(made) / CGFloat(total)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(WidgetStyle.accented(WidgetStyle.progressGold, mode: renderingMode))
                    .frame(width: max(4, proxy.size.width * fraction))
                    .widgetAccentable()
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let remaining = WidgetInlineCopy.compactRemaining(deadline.timeIntervalSince(now))
        var text = "\(snapshot.groupName). \(kind.label), \(remaining) remaining. Week \(snapshot.weekNumber)."
        if let owed {
            if owed.left == 0 {
                text += " All picks in."
            } else {
                text += " \(owed.left) of \(owed.total) picks left."
            }
        }
        return text
    }
}

struct ScoreboardPhaseView: View {
    let snapshot: StandingsSnapshot
    let now: Date
    var linkRows: Bool = false

    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    @Environment(\.showsWidgetContainerBackground) private var systemShowsBackground
    @Environment(\.showsWidgetBackgroundOverride) private var showsBackgroundOverride
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var family: WidgetFamily { familyOverride ?? systemFamily }
    private var showsBackground: Bool { showsBackgroundOverride ?? systemShowsBackground }
    private var enlarged: Bool { !showsBackground }
    private var stale: Bool { WidgetPhase.isStale(snapshot: snapshot, now: now) }

    private var rowLimit: Int {
        switch family {
        case .systemMedium: return 3
        case .systemLarge, .systemExtraLarge: return 6
        default: return 0
        }
    }

    private var games: [StandingsSnapshot.SnapshotGame] {
        WidgetScoreboard.ordered(snapshot.games ?? [], now: now, limit: rowLimit)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.modifier(AccessoryBackground())
        case .accessoryRectangular:
            rectangular.modifier(AccessoryBackground())
        case .accessoryInline:
            EmptyView()
        case .systemSmall:
            stacked.modifier(HomeWidgetBackground(family: family))
        case .systemLarge, .systemExtraLarge:
            stacked.modifier(HomeWidgetBackground(family: family))
        default:
            stacked.modifier(HomeWidgetBackground(family: family))
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetEyebrow(text: "Live · Wk \(snapshot.weekNumber)")
                    Text(snapshot.groupName)
                        .font(WidgetStyle.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                Text(snapshot.weeklyRecord)
                    .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            .widgetLink(linkRows ? WidgetDeepLink.url(phase: .scoreboard, snapshot: snapshot) : nil)
            if !luminanceReduced {
                ForEach(games) { game in
                    SnapshotGameLine(game: game, now: now, stale: stale, snapshot: snapshot, linked: linkRows)
                }
            }
            if stale {
                WidgetUpdatedLine(date: snapshot.updatedAt)
                if family != .systemSmall {
                    WidgetRefreshButton()
                }
            } else if family != .systemSmall, let next = WidgetPhase.nextLockDate(snapshot: snapshot, now: now) {
                Text("Next lock \(next.formatted(.dateTime.hour().minute()))")
                    .font(WidgetStyle.rowFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardLabel)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetEyebrow(text: snapshot.groupName)
            Text(snapshot.weeklyRecord)
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text("Live · Week \(snapshot.weekNumber)")
                .font(WidgetStyle.rowFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreboardLabel)
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Text(snapshot.weeklyRecord)
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .widgetAccentable()
            Text("Live")
                .font(WidgetStyle.eyebrowFont)
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
    var stale: Bool
    var snapshot: StandingsSnapshot
    var linked: Bool

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var status: WidgetPickStatus {
        WidgetScoreboard.pickStatus(game, now: now)
    }

    private var live: Bool {
        !game.isFinal && (game.isLocked || game.kickoff <= now || game.awayScore != nil || game.homeScore != nil)
    }

    var body: some View {
        HStack(spacing: 6) {
            side(name: game.awayShortName, score: game.awayScore, hex: game.awayColorHex, picked: game.userPick == game.awayShortName)
            side(name: game.homeShortName, score: game.homeScore, hex: game.homeColorHex, picked: game.userPick == game.homeShortName)
            Spacer(minLength: 4)
            Text(clock)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let glyph = status.glyph {
                Text(glyph)
                    .foregroundStyle(WidgetStyle.accented(glyphColor, mode: renderingMode))
                    .widgetAccentable()
            }
        }
        .font(WidgetStyle.rowFont)
        .lineLimit(1)
        .widgetLink(linked ? WidgetDeepLink.gameURL(snapshot: snapshot, gameId: game.id) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel)
    }

    private func side(name: String, score: Int?, hex: String?, picked: Bool) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(WidgetStyle.color(hex: hex, mode: renderingMode))
                .frame(width: 3, height: 12)
                .widgetAccentable(renderingMode != .fullColor)
            Text(name)
                .fontWeight(picked ? .bold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let score {
                Text("\(score)")
                    .monospacedDigit()
                    .opacity(stale && live ? 0.45 : 1)
            }
        }
        .foregroundStyle(picked ? WidgetStyle.accented(WidgetStyle.brandRed, mode: renderingMode) : Color.primary)
        .widgetAccentable(picked)
    }

    private var clock: String {
        if let statusText = game.statusText?.trimmingCharacters(in: .whitespacesAndNewlines), !statusText.isEmpty {
            return statusText
        }
        if game.isFinal { return "Final" }
        if live { return "Live" }
        return game.kickoff.formatted(.dateTime.hour().minute())
    }

    private var glyphColor: Color {
        switch status {
        case .winning, .finalWin: return WidgetStyle.winGreen
        case .losing, .finalLoss: return WidgetStyle.brandRed
        default: return .secondary
        }
    }

    private var rowLabel: String {
        let pick = game.userPick.map { ", picked \($0)" } ?? ""
        let mark = status.spokenName
        if game.awayScore != nil || game.homeScore != nil {
            return "\(game.awayShortName) \(game.awayScore ?? 0), \(game.homeShortName) \(game.homeScore ?? 0)\(pick). \(clock). \(mark)."
        }
        return "\(game.awayShortName) at \(game.homeShortName)\(pick). \(clock). \(mark)."
    }
}
