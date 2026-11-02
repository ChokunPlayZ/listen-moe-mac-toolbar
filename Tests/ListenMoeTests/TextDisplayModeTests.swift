import Foundation
import Testing
@testable import ListenMoe

struct TextDisplayModeTests {
    @Test func defaultsToRomajiAndHonorsExistingFurigana() throws {
        let suite = "TextDisplayModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(TextDisplayMode.load(from: defaults) == .romaji)
        defaults.set(true, forKey: "furigana")
        #expect(TextDisplayMode.load(from: defaults) == .furigana)
    }

    @Test(arguments: [false, true], [false, true])
    func migratesLegacyToggles(romanized: Bool, furigana: Bool) throws {
        let suite = "TextDisplayModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(romanized, forKey: "romanized")
        defaults.set(furigana, forKey: "furigana")
        let expected: TextDisplayMode = furigana || !romanized ? .furigana : .romaji
        #expect(TextDisplayMode.load(from: defaults) == expected)
        defaults.set("unknown", forKey: "textDisplayMode")
        #expect(TextDisplayMode.load(from: defaults) == expected)
    }

    @Test(arguments: TextDisplayMode.allCases)
    func storedModeTakesPrecedenceOverLegacyToggles(mode: TextDisplayMode) throws {
        let suite = "TextDisplayModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(mode == .furigana, forKey: "romanized")
        defaults.set(mode == .romaji, forKey: "furigana")
        defaults.set(mode.rawValue, forKey: "textDisplayMode")
        #expect(TextDisplayMode.load(from: defaults) == mode)
    }
}
