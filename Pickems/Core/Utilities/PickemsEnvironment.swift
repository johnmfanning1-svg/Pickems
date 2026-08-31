import SwiftUI

extension View {
    /// Forwards AppState + theme into presented content.
    /// Sheets can lose `@Environment(AppState.self)` and trap with EXC_BREAKPOINT
    /// (`EnvironmentValues.subscript.getter` → `SheetBridge.present`) — Apple's 1.0 review crash.
    func pickemsEnvironment(_ appState: AppState) -> some View {
        environment(appState)
            .environment(\.themePalette, appState.appTheme.palette)
            .pickemsSheetChrome()
            // Help opened from inside this sheet must present here, not at the
            // root host — a root help sheet would replace this one.
            .presentsHelp()
    }

    /// iOS 26 sheets clip the nav bar into the rounded top. A visible grabber plus
    /// an opaque toolbar keeps Cancel / title / trailing items off the edge.
    /// `.scrolls` stops a List/ScrollView layout pass from being treated as the
    /// sheet's interactive dismiss (content flashes, then the sheet closes).
    func pickemsSheetChrome() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(PickemsColors.background)
            .toolbarBackground(PickemsColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
