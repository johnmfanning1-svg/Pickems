import SwiftUI

struct SpreadEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let game: SlateGame
    let onSave: (Double, String) -> Void

    @State private var spreadValue: Double
    @State private var favoriteIsHome: Bool
    @State private var didEdit = false

    init(game: SlateGame, onSave: @escaping (Double, String) -> Void) {
        self.game = game
        self.onSave = onSave
        _spreadValue = State(initialValue: abs(game.spread))
        _favoriteIsHome = State(initialValue: game.spreadTeamId == game.homeTeamId)
    }

    private var serverFavoriteIsHome: Bool { game.spreadTeamId == game.homeTeamId }

    private var draft: SpreadDraftRefresh.Draft {
        SpreadDraftRefresh.Draft(spread: spreadValue, favoriteIsHome: favoriteIsHome, didEdit: didEdit)
    }

    /// Stepper and picker go through these so a server refresh can write
    /// `spreadValue` without counting as an edit.
    private var spreadBinding: Binding<Double> {
        Binding(
            get: { spreadValue },
            set: { (newValue: Double) in
                didEdit = true
                spreadValue = newValue
            }
        )
    }

    private var favoriteBinding: Binding<Bool> {
        Binding(
            get: { favoriteIsHome },
            set: { (newValue: Bool) in
                didEdit = true
                favoriteIsHome = newValue
            }
        )
    }

    private func applyServerLine() {
        let next = SpreadDraftRefresh.afterServerLine(
            draft,
            spread: game.spread,
            favoriteIsHome: serverFavoriteIsHome
        )
        spreadValue = next.spread
        favoriteIsHome = next.favoriteIsHome
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(game.awayTeamAbbreviation) \(game.matchupSeparator) \(game.homeTeamAbbreviation)")
                        .font(.headline)
                }

                Section("Spread") {
                    Stepper(
                        "Line: \(spreadValue.formatted(.number.precision(.fractionLength(1))))",
                        value: spreadBinding,
                        in: 0...50,
                        step: 0.5
                    )
                    Picker("Favorite", selection: favoriteBinding) {
                        Text(game.homeTeamAbbreviation).tag(true)
                        Text(game.awayTeamAbbreviation).tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Preview: \(favoriteIsHome ? game.homeTeamAbbreviation : game.awayTeamAbbreviation) -\(spreadValue.formatted(.number.precision(.fractionLength(1))))")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                    if SpreadDraftRefresh.showsLineChangedWarning(
                        draft: draft,
                        serverSpread: game.spread,
                        serverFavoriteIsHome: serverFavoriteIsHome
                    ) {
                        Text("The slate line changed. Save keeps your edit.")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Edit Spread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let spreadTeamId = favoriteIsHome ? game.homeTeamId : game.awayTeamId
                        onSave(spreadValue, spreadTeamId)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: game.spread) { _, _ in applyServerLine() }
        .onChange(of: game.spreadTeamId) { _, _ in applyServerLine() }
        .presentationDetents([.medium])
    }
}
