import SwiftUI

extension ThemeManager {
    private struct ThemeUndoSnapshot: Codable {
        let themeColorConfig: ThemeColorConfig
        let petChatSkinTheme: PetChatSkinTheme
    }

    private var lastThemeSnapshotKey: String { "theme_last_snapshot_v1" }

    @discardableResult
    func saveCurrentThemeAsSet(named rawName: String?) -> UserCustomTheme {
        var newConfig = themeColorConfig
        let fallback = "我的主题\(Date().formatted(date: .omitted, time: .shortened))"
        let resolved = (rawName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? rawName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : fallback

        // 同名时先移除旧条目，避免无意义增长。
        newConfig.customColorConfig.userCustomThemes.removeAll {
            $0.name.localizedCaseInsensitiveCompare(resolved) == .orderedSame
        }
        let saved = newConfig.customColorConfig.saveAsNewTheme(name: resolved)
        newConfig.colorSchemeMode = .custom
        newConfig.customColorConfig.selectedPresetId = nil
        themeColorConfig = newConfig
        return saved
    }

    @discardableResult
    func applyThemeSet(named rawName: String) -> Bool {
        let keyword = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return false }

        if let preset = CustomColorPresets.all.first(where: {
            $0.name.lowercased() == keyword || keyword.contains($0.name.lowercased())
        }) {
            applyThemePreset(preset)
            return true
        }

        if let custom = themeColorConfig.customColorConfig.userCustomThemes.first(where: {
            $0.name.lowercased() == keyword || keyword.contains($0.name.lowercased())
        }) {
            var newConfig = themeColorConfig
            newConfig.colorSchemeMode = .custom
            newConfig.customColorConfig.selectedPresetId = nil
            newConfig.customColorConfig.currentCustom = custom
            newConfig.customColorConfig.currentCustom.updatedAt = Date()
            themeColorConfig = newConfig
            return true
        }

        return false
    }

    func availableThemeSetNames() -> [String] {
        let presetNames = CustomColorPresets.all.map(\.name)
        let customNames = themeColorConfig.customColorConfig.userCustomThemes.map(\.name)
        return presetNames + customNames
    }

    func deleteThemeSet(id: String) {
        var newConfig = themeColorConfig
        newConfig.customColorConfig.deleteCustomTheme(id: id)
        themeColorConfig = newConfig
    }

    func restoreDefaultThemeSet() {
        applyThemePreset(CustomColorPresets.monicaPink)
        petChatSkinTheme = .classic
    }

    func captureThemeSnapshot() {
        let snapshot = ThemeUndoSnapshot(
            themeColorConfig: themeColorConfig,
            petChatSkinTheme: petChatSkinTheme
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        UserDefaults.standard.set(data, forKey: lastThemeSnapshotKey)
    }

    var canRestoreLastThemeSnapshot: Bool {
        UserDefaults.standard.data(forKey: lastThemeSnapshotKey) != nil
    }

    @discardableResult
    func restoreLastThemeSnapshot() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: lastThemeSnapshotKey),
              let snapshot = try? JSONDecoder().decode(ThemeUndoSnapshot.self, from: data) else {
            return false
        }

        let currentSnapshot = ThemeUndoSnapshot(
            themeColorConfig: themeColorConfig,
            petChatSkinTheme: petChatSkinTheme
        )

        themeColorConfig = snapshot.themeColorConfig
        petChatSkinTheme = snapshot.petChatSkinTheme

        if let currentData = try? JSONEncoder().encode(currentSnapshot) {
            UserDefaults.standard.set(currentData, forKey: lastThemeSnapshotKey)
        }

        return true
    }

    func applyThemePreset(_ preset: ThemePreset) {
        var newConfig = themeColorConfig
        newConfig.colorSchemeMode = .custom
        newConfig.customColorConfig.selectedPresetId = preset.id
        syncPresetToCurrentCustom(preset: preset, config: &newConfig)
        themeColorConfig = newConfig
    }

    private func syncPresetToCurrentCustom(preset: ThemePreset, config: inout ThemeColorConfig) {
        config.customColorConfig.currentCustom.textPrimaryRGBA = preset.textPrimaryRGBA
        config.customColorConfig.currentCustom.textSecondaryRGBA = preset.textSecondaryRGBA
        config.customColorConfig.currentCustom.textTertiaryRGBA = preset.textTertiaryRGBA
        config.customColorConfig.currentCustom.textAccentRGBA = preset.textAccentRGBA
        config.customColorConfig.currentCustom.cardConfig = preset.cardConfig

        if preset.supportsDarkMode {
            config.customColorConfig.currentCustom.darkTextPrimaryRGBA = preset.darkTextPrimaryRGBA ?? preset.textPrimaryRGBA
            config.customColorConfig.currentCustom.darkTextSecondaryRGBA = preset.darkTextSecondaryRGBA ?? preset.textSecondaryRGBA
            config.customColorConfig.currentCustom.darkTextTertiaryRGBA = preset.darkTextTertiaryRGBA ?? preset.textTertiaryRGBA
            config.customColorConfig.currentCustom.darkTextAccentRGBA = preset.darkTextAccentRGBA ?? preset.textAccentRGBA
            config.customColorConfig.currentCustom.darkCardConfig = preset.darkCardConfig ?? preset.cardConfig
        }
        config.customColorConfig.currentCustom.updatedAt = Date()
    }
}
