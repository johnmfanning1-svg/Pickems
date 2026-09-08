import SwiftUI

/// Commissioner controls: tone, editable share copy, then send.
struct CommissionerLeagueRecapPanel: View {
    let group: PickemGroup
    let week: WeekSummary
    let entries: [StandingEntry]
    var picks: [UserPick] = []
    var games: [SlateGame] = []
    var awards: WeekAwards?

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @AppStorage(LeagueRecapTone.storageKey) private var toneRaw = LeagueRecapTone.moderate.rawValue
    @State private var draftText = ""
    @State private var lastGenerated = ""

    private var tone: LeagueRecapTone {
        LeagueRecapTone(rawValue: toneRaw) ?? .moderate
    }

    private var recap: LeagueWeekRecap {
        LeagueWeekRecapGenerator.recap(
            groupName: group.name,
            week: week,
            entries: entries,
            picks: picks,
            games: games,
            awards: awards,
            tone: tone
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LeagueWeekRecapCard(recap: recap)

            if let awards {
                WeekAwardsBanner(awards: awards)
                    .padding(.horizontal)
            }

            tonePicker
                .padding(.horizontal)

            editor
                .padding(.horizontal)

            if !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ShareTextButton(text: draftText, groupId: group.id, weekId: week.id)
                    .padding(.horizontal)
            }
        }
        .onAppear { syncDraft(force: true) }
        .onChange(of: week.id) { _, _ in syncDraft(force: true) }
        .onChange(of: toneRaw) { _, _ in syncDraft(force: true) }
        .onChange(of: recap.shareText) { _, _ in syncDraft(force: false) }
    }

    private func syncDraft(force: Bool) {
        let generated = recap.shareText
        if force || draftText == lastGenerated {
            draftText = generated
        }
        lastGenerated = generated
    }

    private var tonePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            HStack(spacing: 8) {
                ForEach(LeagueRecapTone.allCases) { option in
                    Button {
                        toneRaw = option.rawValue
                        PickemsHaptics.selection()
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(tone == option ? theme.onAccent : PickemsColors.textPrimary)
                            .background(
                                tone == option ? theme.accent : PickemsColors.cardBackground,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tone == option ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("League recap tone")
        }
    }

    private var draftCharacterCount: Int {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edit before sending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                Spacer()
                if appState.chatService.chatEnabled {
                    Text("\(draftCharacterCount)/\(ChatMessage.maxTextLength)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            draftCharacterCount > ChatMessage.maxTextLength
                                ? PickemsColors.warning
                                : PickemsColors.textSecondary
                        )
                        .accessibilityLabel("\(draftCharacterCount) of \(ChatMessage.maxTextLength) characters")
                }
                if draftText != recap.shareText {
                    Button("Reset") {
                        draftText = recap.shareText
                        PickemsHaptics.selection()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                }
            }
            TextEditor(text: $draftText)
                .font(.body)
                .foregroundStyle(PickemsColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, maxHeight: 220)
                .padding(10)
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .accessibilityLabel("League recap text")
        }
    }
}
