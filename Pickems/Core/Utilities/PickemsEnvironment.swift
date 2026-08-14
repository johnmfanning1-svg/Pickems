import SwiftUI

extension View {
    /// Forwards AppState + theme into presented content.
    /// Sheets can lose `@Environment(AppState.self)` and trap with EXC_BREAKPOINT
    /// (`EnvironmentValues.subscript.getter` → `SheetBridge.present`) — Apple's 1.0 review crash.
    func pickemsEnvironment(_ appState: AppState) -> some View {
        environment(appState)
            .environment(\.themePalette, appState.appTheme.palette)
            .pickemsSheetChrome()
    }

    /// iOS 26 sheets clip the nav bar into the rounded top. A visible grabber plus
    /// an opaque toolbar keeps Cancel / title / trailing items off the edge.
    func pickemsSheetChrome() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationBackground(PickemsColors.background)
            .toolbarBackground(PickemsColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
