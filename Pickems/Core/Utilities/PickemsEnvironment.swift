import SwiftUI

extension View {
    /// Forwards AppState + theme into presented content.
    /// Sheets can lose `@Environment(AppState.self)` and trap with EXC_BREAKPOINT
    /// (`EnvironmentValues.subscript.getter` → `SheetBridge.present`) — Apple's 1.0 review crash.
    func pickemsEnvironment(_ appState: AppState) -> some View {
        environment(appState)
            .environment(\.themePalette, appState.appTheme.palette)
    }
}
