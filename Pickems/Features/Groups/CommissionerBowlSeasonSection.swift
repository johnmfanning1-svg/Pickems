import SwiftUI

/// Bowl Season (Mode A) commissioner block. Coordinators see a read-only summary.
struct CommissionerBowlSeasonSection: View {
    let group: PickemGroup
    @Binding var rules: GroupRules
    let canEditMode: Bool
    let pickemsWeekNumber: Int?
    let espnSeasonType: Int?
    let leagueWeeks: [WeekSummary]

  @State private var pickCount: Int

  init(
    group: PickemGroup,
    rules: Binding<GroupRules>,
    canEditMode: Bool,
    pickemsWeekNumber: Int?,
    espnSeasonType: Int?,
    leagueWeeks: [WeekSummary] = []
  ) {
    self.group = group
    _rules = rules
    self.canEditMode = canEditMode
    self.pickemsWeekNumber = pickemsWeekNumber
    self.espnSeasonType = espnSeasonType
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

    private var available: Bool {
        CFBBowlSeason.commissionerSettingsAvailable(
            pickemsWeekNumber: pickemsWeekNumber,
            espnSeasonType: espnSeasonType
        )
    }

    var body: some View {
        if available {
            Section {
                if canEditMode {
                    Toggle("Run a Bowl Season week", isOn: enabledBinding)
                        .listRowBackground(PickemsColors.cardBackground)

                    if settings.wrappedValue.isEnabled {
                        modeRow
                        pickCountRow
                        rollingSuggestion
                        secondWeekToggle
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
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.isEnabled },
            set: { on in
                var next = settings.wrappedValue
                next.isEnabled = on
                next.mode = .modeA
                if on, next.pickCount == nil {
                    next.pickCount = rules.slateSize
                    pickCount = next.resolvedPickCount(rules: rules)
                }
                settings.wrappedValue = next
            }
        )
    }

    private var modeRow: some View {
        LabeledContent("Mode", value: "Pick bowl games (Mode A)")
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
            Text("Rolling lock is recommended for bowl weeks — each game locks at kickoff.")
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
            if !rules.pickDeadline.isRolling {
                Text("Your league still defaults to first-kickoff lock for regular weeks. Bowl weeks will suggest rolling when minted.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .listRowBackground(PickemsColors.cardBackground)
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
                LabeledContent("Bowl Season", value: "Mode A — \(pickCount) games")
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

    private var footer: String {
        if !canEditMode {
            return "Coordinators can run bowl weeks but cannot change the bowl mode."
        }
        if standingsToggleLocked {
            return "A bowl week is already scored — season standings inclusion can’t be changed."
        }
        return """
        After the Dec 6 selection show, build a slate from the postseason catalog. \
        Army–Navy stays on Week 15; Celebration Bowl belongs on a bowl week. \
        Mode B (all bowls in one contest) is coming later.
        """
    }
}