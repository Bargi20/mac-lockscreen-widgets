import Foundation

/// The app speaks Italian on Macs set to Italian and English everywhere else.
/// `Locale.preferredLanguages` also follows a per-app language chosen in System Settings.
enum L10n {
    static let italian: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("it")

    /// Language code for web services (city search).
    static var code: String { italian ? "it" : "en" }
}

/// Picks the Italian or the English text for the system language.
func tr(_ it: String, _ en: String) -> String {
    L10n.italian ? it : en
}
