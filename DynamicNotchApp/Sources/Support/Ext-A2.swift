// Stored-setting key of the first-launch intro (RootView / IntroView).
import Foundation

extension StoredKeys {
    /// Whether the intro is still to be shown (the `license` / `trialInitialTime` keys of the
    /// original were removed with its licensing code).
    static let intro = Key<Bool>(SettingKey.intro, default: true)
}
