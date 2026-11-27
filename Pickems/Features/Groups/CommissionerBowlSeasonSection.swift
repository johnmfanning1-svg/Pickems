import SwiftUI

/// Bowl Season commissioner block. Coordinators see a read-only summary.
struct CommissionerBowlSeasonSection: View {
    let group: PickemGroup
    @Binding var rules: GroupRules
    let canEditMode: Bool
    let leagueWeeks: [WeekSummary]

    @State private var pickCount: Int

    init(
        group: PickemGroup,
        rules: Binding<GroupRules>,
        canEditMode: Bool,
        leagueWeeks: [WeekSummary] = []
    ) {
        self.group = group
        _rules = rules
        self.canEditMode = canEditMode
        self.leagueWeeks = leagueWeeks
        let settings = rules.wrappedValue.bowlSeason ?? .default
        _pickCount = State(initialValue: settings.resolvedPickCount(rules: rules.wrappedValue))
    }

    private var settings: Binding<CFBBowlSeason.Settings> {
        Binding(
            get: { rules.bowlSeason ?? .default },
            set: { rules.bowlSeason = $0 }
        )
    }

    private var modeBinding: Binding<CFBBowlSeason.Mode> {
        Binding(
            get: { settings.wrappedValue.mode },
            set: { mode in
                var next = settings.wrappedValue
                next.mode = mode
                settings.wrappedValue = next
            }
        )
    }

    var body: some View {
        Section {
            if canEditMode {
                Toggle("Run a Bowl Season week", isOn: enabledBinding)
                    .listRowBackground(PickemsColors.cardBackground)

                if settings.wrappedValue.isEnabled {
                    modePicker
                    if settings.wrappedValue.mode == .modeA {
                        pickCountRow
                    }
                    rollingSuggestion
                    if settings.wrappedValue.mode == .modeA {
                        secondWeekToggle
                    }
                    seasonStandingsToggle
                }
            } else {
                coordinatorSummary
            }
        } header: {
            Text("Bowl Season")
        } footer: {
            Text(footer)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.isEnabled },
            set: { on in
                var next = settings.wrappedValue
                next.isEnabled = on
                if on, next.pickCount == nil {
                    next.pickCount = rules.slateSize
                    pickCount = next.resolvedPickCount(rules: rules)
                }
                settings.wrappedValue = next
            }
        )
    }

    private var modePicker: some View {
        Picker("Bowl format", selection: modeBinding) {
            ForEach(CFBBowlSeason.Mode.allCases) { mode in
                Text(mode.commissionerLabel).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .listRowBackground(PickemsColors.cardBackground)
    }

    private var pickCountRow: some View {
        Stepper("Bowl games to pick: \(pickCount)", value: $pickCount, in: 1...20)
            .listRowBackground(PickemsColors.cardBackground)
            .onChange(of: pickCount) { _, value in
                var next = settings.wrappedValue
                next.pickCount = value
                settings.wrappedValue = next
            }
    }

    private var rollingSuggestion: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rollingCopy)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private var rollingCopy: String {
        if settings.wrappedValue.mode == .modeB {
            return "Every bowl game uses rolling lock — each game locks at kickoff, including CFP games as they are scheduled."
        }
        return "Rolling lock is recommended for bowl weeks — each game locks at kickoff."
    }

    private var secondWeekToggle: some View {
        Toggle("Add a second bowl week (NY6 & CFP)", isOn: secondWeekBinding)
            .listRowBackground(PickemsColors.cardBackground)
    }

    private var secondWeekBinding: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.includesSecondWeek },
            set: { on in
                var next = settings.wrappedValue
                next.includesSecondWeek = on
                settings.wrappedValue = next
            }
        )
    }

    private var standingsToggleLocked: Bool {
        CFBBowlSeason.standingsToggleLocked(weeks: leagueWeeks)
    }

    private var seasonStandingsToggle: some View {
        Toggle("Bowl results count toward season standings", isOn: seasonStandingsBinding)
            .disabled(standingsToggleLocked)
            .listRowBackground(PickemsColors.cardBackground)
    }

    private var seasonStandingsBinding: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.countsTowardSeasonStandings },
            set: { on in
                guard !standingsToggleLocked else { return }
                var next = settings.wrappedValue
                next.countsTowardSeasonStandings = on
                settings.wrappedValue = next
            }
        )
    }

    private var coordinatorSummary: some View {
        Group {
            if settings.wrappedValue.isEnabled {
                LabeledContent("Bowl Season", value: coordinatorModeLabel)
                LabeledContent(
                    "Season standings",
                    value: settings.wrappedValue.countsTowardSeasonStandings ? "Include bowls" : "Bowls separate"
                )
            } else {
                Text("Bowl Season is off for this league.")
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private var coordinatorModeLabel: String {
        switch settings.wrappedValue.mode {
        case .modeA:
            return "\(CFBBowlSeason.Mode.modeA.commissionerLabel) — \(pickCount) games"
        case .modeB:
            return CFBBowlSeason.Mode.modeB.commissionerLabel
        }
    }

    private var footer: String {
        if !canEditMode {
            return "Coordinators can run bowl weeks but cannot change the bowl format."
        }
        if standingsToggleLocked {
            return "A bowl week is already scored — season standings inclusion can't be changed."
        }
        if settings.wrappedValue.mode == .modeB {
            return """
            Pick every FBS bowl and the full CFP bracket in one contest starting Dec 6. \
            New CFP matchups appear as ESPN schedules them — you don't rebuild the slate. \
            Army–Navy stays on Week 15.
            """
        }
        return """
        After the Dec 6 selection show, build a slate from the postseason catalog. \
        Army–Navy stays on Week 15; Celebration Bowl belongs on a bowl week.
        """
    }
}