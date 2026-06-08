import Foundation

/// User-editable ArgusDesk preferences persisted by macOS.
///
/// Server definitions remain in `servers.json`. This store only persists
/// lightweight app behavior and notification settings appropriate for
/// `UserDefaults`.
struct AppPreferences {
    /// Local Mac status refresh interval in seconds.
    let localRefreshSeconds: Int

    /// Remote server refresh interval in seconds.
    let remoteRefreshSeconds: Int

    /// Whether warning/error state changes should send notifications.
    let notificationsEnabled: Bool

    /// Whether recovery transitions should send notifications.
    let recoveryNotificationsEnabled: Bool
}

/// Reads and writes app preferences with `UserDefaults`.
struct PreferencesStore {
    /// Keys owned by ArgusDesk in the defaults database.
    private enum Key {
        static let localRefreshSeconds = "localRefreshSeconds"
        static let remoteRefreshSeconds = "remoteRefreshSeconds"
        static let notificationsEnabled = "notificationsEnabled"
        static let recoveryNotificationsEnabled = "recoveryNotificationsEnabled"
    }

    /// Defaults database used for persistence.
    private let defaults: UserDefaults

    /// Creates a preferences store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads stored values, falling back to the current JSON configuration.
    func load(fallback: AppPreferences) -> AppPreferences {
        AppPreferences(
            localRefreshSeconds: positiveInteger(forKey: Key.localRefreshSeconds) ?? fallback.localRefreshSeconds,
            remoteRefreshSeconds: positiveInteger(forKey: Key.remoteRefreshSeconds) ?? fallback.remoteRefreshSeconds,
            notificationsEnabled: storedBoolean(forKey: Key.notificationsEnabled) ?? fallback.notificationsEnabled,
            recoveryNotificationsEnabled: storedBoolean(forKey: Key.recoveryNotificationsEnabled) ?? fallback.recoveryNotificationsEnabled
        )
    }

    /// Persists the current app preferences.
    func save(_ preferences: AppPreferences) {
        defaults.set(max(1, preferences.localRefreshSeconds), forKey: Key.localRefreshSeconds)
        defaults.set(max(1, preferences.remoteRefreshSeconds), forKey: Key.remoteRefreshSeconds)
        defaults.set(preferences.notificationsEnabled, forKey: Key.notificationsEnabled)
        defaults.set(preferences.recoveryNotificationsEnabled, forKey: Key.recoveryNotificationsEnabled)
    }

    /// Returns a stored positive integer, ignoring invalid defaults.
    private func positiveInteger(forKey key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }

        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    /// Returns a stored Boolean only when the key has been explicitly saved.
    private func storedBoolean(forKey key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }

        return defaults.bool(forKey: key)
    }
}
