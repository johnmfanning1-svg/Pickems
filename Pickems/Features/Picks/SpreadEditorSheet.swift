import SwiftUI

struct SpreadEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let game: SlateGame
    let onSave: (Double, String) -> Void

    @State private var spreadValue: Double
    @State private var favoriteIsHome: Bool

    init(game: SlateGame, onSave: @escaping (Double, String) -> Void) {
        self.game = game
        self.onSave = onSave
        _spreadValue = State(initialValue: abs(game.spread))
        _favoriteIsHome = State(initialValue: game.spreadTeamId == game.homeTeamId)
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
                        value: $spreadValue,
                        in: 0...50,
                        step: 0.5
                    )
                    Picker("Favorite", selection: $favoriteIsHome) {
                        Text(game.homeTeamAbbreviation).tag(true)
                        Text(game.awayTeamAbbreviation).tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Preview: \(favoriteIsHome ? game.homeTeamAbbreviation : game.awayTeamAbbreviation) -\(spreadValue.formatted(.number.precision(.fractionLength(1))))")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
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
        .presentationDetents([.medium])
    }
}
