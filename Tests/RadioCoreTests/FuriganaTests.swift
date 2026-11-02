import Testing
import RadioCore

struct FuriganaTests {
    @Test func generatesJapaneseKanaReadingsForKanji() {
        let segments = Furigana.segments(for: "進撃の巨人")
        #expect(segments.map(\.text).joined() == "進撃の巨人")
        #expect(segments.contains { $0.text == "進撃" && $0.reading == "しんげき" })
        #expect(segments.contains { $0.text == "巨人" && $0.reading == "きょじん" })
        #expect(segments.first { $0.text == "の" }?.reading == nil)
    }

    @Test(arguments: ["", "Only English", "ひらがな カタカナ", "데이식스"])
    func leavesNonKanjiTextUnannotated(text: String) {
        let segments = Furigana.segments(for: text)
        #expect(segments.map(\.text).joined() == text)
        #expect(segments.allSatisfy { $0.reading == nil })
    }

    @Test func preservesWhitespacePunctuationAndEmoji() {
        let text = "🎵 東京 物語！\n小倉唯 / Guest"
        let segments = Furigana.segments(for: text)
        #expect(segments.map(\.text).joined() == text)
        #expect(segments.contains { $0.reading != nil })
    }
}
