import Foundation
import SwiftUI

/// Profile appearance choice. Stored in the app-group defaults so the widget
/// and Live Activity read the same value as the app.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance.preference"

    /// Unset installs stay dark. That was the only appearance before this control existed.
    static let defaultPreference: AppearancePreference = .dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` follows the device appearance. Light and dark are fixed.
    var resolvedColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func resolve(stored value: String?) -> AppearancePreference {
        guard let value, let match = AppearancePreference(rawValue: value) else {
            return defaultPreference
        }
        return match
    }
}

enum AppearancePreferenceStore {
    /// One object for the suite. `@AppStorage` only observes the instance it was
    /// given. A new `UserDefaults(suiteName:)` on each access still stores the
    /// string (the Profile control stays on Light) but never tells the window,
    /// so `preferredColorScheme` stays dark and does not override the device.
    static let appGroupDefaults: UserDefaults = {
        UserDefaults(suiteName: PickemsAppGroup.suiteName) ?? .standard
    }()

    static func preference(defaults: UserDefaults = appGroupDefaults) -> AppearancePreference {
        AppearancePreference.resolve(stored: defaults.string(forKey: AppearancePreference.storageKey))
    }

    static func set(_ preference: AppearancePreference, defaults: UserDefaults = appGroupDefaults) {
        defaults.set(preference.rawValue, forKey: AppearancePreference.storageKey)
    }

    static func resolvedColorScheme(defaults: UserDefaults = appGroupDefaults) -> ColorScheme? {
        preference(defaults: defaults).resolvedColorScheme
    }
}
