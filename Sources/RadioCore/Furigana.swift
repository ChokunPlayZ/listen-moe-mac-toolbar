import CoreFoundation
import Foundation

public struct FuriganaSegment: Equatable, Sendable {
    public let text: String
    public let reading: String?
}

public enum Furigana {
    public static func segments(for text: String) -> [FuriganaSegment] {
        guard containsKanji(text) else { return [FuriganaSegment(text: text, reading: nil)] }
        let source = text as NSString
        let locale = Locale(identifier: "ja_JP") as NSLocale as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: source.length),
            kCFStringTokenizerUnitWord, locale
        )
        var result: [FuriganaSegment] = []
        var cursor = 0
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > cursor {
                result.append(FuriganaSegment(
                    text: source.substring(with: NSRange(location: cursor, length: range.location - cursor)), reading: nil
                ))
            }
            let word = source.substring(with: NSRange(location: range.location, length: range.length))
            let transcription = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String
            let reading = containsKanji(word)
                ? transcription?.applyingTransform(StringTransform("Latin-Hiragana"), reverse: false)
                : nil
            result.append(FuriganaSegment(text: word, reading: reading == word ? nil : reading))
            cursor = range.location + range.length
        }
        if cursor < source.length {
            result.append(FuriganaSegment(
                text: source.substring(from: cursor), reading: nil
            ))
        }
        return result.isEmpty ? [FuriganaSegment(text: text, reading: nil)] : result
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value) || (0x20000...0x323AF).contains($0.value)
                || $0.value == 0x3005 // Japanese iteration mark: 々
        }
    }
}
