import Foundation

enum TextDisplayMode: String, CaseIterable {
    case romaji, furigana

    var title: String {
        switch self {
        case .romaji: "Romaji"
        case .furigana: "Furigana"
        }
    }

    static func load(from defaults: UserDefaults) -> Self {
        if let value = defaults.string(forKey: "textDisplayMode"), let mode = Self(rawValue: value) {
            return mode
        }
        // Keep existing Japanese text preferences; resolve conflicting toggles in favor of furigana.
        let romanized = defaults.object(forKey: "romanized") as? Bool ?? true
        return defaults.bool(forKey: "furigana") || !romanized ? .furigana : .romaji
    }
}
