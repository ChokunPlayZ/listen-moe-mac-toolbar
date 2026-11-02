import CoreFoundation
import Foundation

enum Romanization {
    static func fallback(for text: String) -> String {
        guard containsJapaneseOrKorean(text) else { return text }
        let source = text as NSString
        // A generic toLatin transform reads kanji as Chinese. Use the Japanese
        // tokenizer's contextual readings instead, as we do for furigana.
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: source.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja_JP") as NSLocale as CFLocale
        )
        var result = ""
        var cursor = 0
        var previousWasConverted = false
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > cursor {
                result += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            let word = source.substring(with: NSRange(location: range.location, length: range.length))
            let reading = containsJapaneseOrKorean(word)
                ? CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
                : nil
            let replacement = reading?.nonBlank ?? word
            let converted = replacement != word
            // Separate inferred words, but preserve existing Latin names such as
            // DAY6 and SEASON2, whitespace, punctuation, and emoji verbatim.
            if range.location == cursor, previousWasConverted || converted,
               let last = result.unicodeScalars.last, let first = replacement.unicodeScalars.first,
               CharacterSet.alphanumerics.contains(last), CharacterSet.alphanumerics.contains(first) {
                result += " "
            }
            result += replacement
            cursor = range.location + range.length
            previousWasConverted = converted
        }
        if cursor < source.length { result += source.substring(from: cursor) }
        return result
    }

    private static func containsJapaneseOrKorean(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            switch $0.value {
            case 0x3005, 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F,
                 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF,
                 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF:
                true
            default:
                false
            }
        }
    }
}
